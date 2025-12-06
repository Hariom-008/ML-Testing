import Foundation
import simd

// MARK: - Landmark Distance Calculations (Matching Android Logic)
extension FaceManager {
    
    /// Calculates angle at vertex B for triangle ABC
    /// Returns angle in radians
    @inline(__always)
    private func angleAtVertex(_ a: (x: Float, y: Float),
                               _ b: (x: Float, y: Float),
                               _ c: (x: Float, y: Float)) -> Float {
        // Vectors from B to A and B to C
        let v1x = a.x - b.x
        let v1y = a.y - b.y
        let v2x = c.x - b.x
        let v2y = c.y - b.y
        
        // Dot product
        let dot = v1x * v2x + v1y * v2y
        
        // Magnitudes
        let mag1 = sqrtf(v1x * v1x + v1y * v1y)
        let mag2 = sqrtf(v2x * v2x + v2y * v2y)
        
        guard mag1 > 0, mag2 > 0 else { return 0 }
        
        // Cosine of angle (clamped to [-1, 1])
        let cosAngle = (dot / (mag1 * mag2)).clamped(to: -1...1)
        
        // Return angle in radians
        return acosf(cosAngle)
    }
    
    /// Proper rounding to 4 decimal places
    @inline(__always)
    private func round4(_ x: Float) -> Float {
        let factor: Float = 10_000  // 10^4
        return (x * factor).rounded() / factor
    }
    
    /// NEW: Calculate pattern matching Android's exact logic
    /// Expected output: 363 elements
    /// - 1: Reference distance (33-263, NOT normalized)
    /// - 135: Mandatory×Mandatory (excluding 33-263 pair), normalized
    /// - 10: Optional chain (ring), normalized
    /// - 170: Optional×Mandatory, normalized
    /// - 47: Angles from angleTriples
    func calculateOptionalAndMandatoryDistances() {
        guard !NormalizedPoints.isEmpty else {
            print("⚠️ NormalizedPoints is empty, cannot compute pattern vector")
            return
        }
        
        var allDistances: [Float] = []
        
        let mand = mandatoryLandmarkPoints
        let opt = selectedOptionalLandmarks
        
        // Validate indices
        let maxIdx = max(
            mand.max() ?? 0,
            opt.max() ?? 0,
            angleTriples.flatMap { [$0.0, $0.1, $0.2] }.max() ?? 0
        )
        
        guard maxIdx < NormalizedPoints.count else {
            print("⚠️ Invalid landmark index \(maxIdx) for NormalizedPoints.count = \(NormalizedPoints.count)")
            return
        }
        
        // Helper for distance
        @inline(__always)
        func d(_ i: Int, _ j: Int) -> Float {
            let p1 = NormalizedPoints[i]
            let p2 = NormalizedPoints[j]
            return Helper.shared.calculateDistance(p1, p2)
        }
        
        // ----------------------------------------------------------------
        // 1) FIRST ELEMENT: Reference distance 33-263 (RAW, not normalized)
        // ----------------------------------------------------------------
        let p33 = NormalizedPoints[33]
        let p263 = NormalizedPoints[263]
        let dRef = Helper.shared.calculateDistance(p33, p263)
        
        allDistances.append(round4(dRef))
        
        print("📏 Reference distance (33-263): \(round4(dRef))")
        
        // Safety check
        guard dRef > 1e-6 else {
            print("❌ Reference distance too small, cannot normalize")
            return
        }
        
        // ----------------------------------------------------------------
        // 2) MANDATORY × MANDATORY (normalized, skip 33-263 pair)
        // ----------------------------------------------------------------
        let mandatoryStart = allDistances.count
        for i in 0..<mand.count {
            let idxA = mand[i]
            for j in (i + 1)..<mand.count {
                let idxB = mand[j]
                
                // Skip 33-263 pair (already added as reference)
                if (idxA == 33 && idxB == 263) || (idxA == 263 && idxB == 33) {
                    continue
                }
                
                let dist = d(idxA, idxB)
                allDistances.append(round4(dist / dRef))
            }
        }
        let mandatoryCount = allDistances.count - mandatoryStart
        
        // ----------------------------------------------------------------
        // 3) OPTIONAL CHAIN (ring topology, normalized)
        // ----------------------------------------------------------------
        let optionalStart = allDistances.count
        for i in 0..<opt.count {
            let idxA = opt[i]
            let idxB = opt[(i + 1) % opt.count]  // Wrap around
            
            let dist = d(idxA, idxB)
            allDistances.append(round4(dist / dRef))
        }
        let optionalChainCount = allDistances.count - optionalStart
        
        // ----------------------------------------------------------------
        // 4) OPTIONAL × MANDATORY (bipartite, normalized)
        // ----------------------------------------------------------------
        let bipartiteStart = allDistances.count
        for optIdx in opt {
            for manIdx in mand {
                let dist = d(optIdx, manIdx)
                allDistances.append(round4(dist / dRef))
            }
        }
        let bipartiteCount = allDistances.count - bipartiteStart
        
        // ----------------------------------------------------------------
        // 5) ANGLES from angleTriples
        // ----------------------------------------------------------------
        let anglesStart = allDistances.count
        for (aIdx, bIdx, cIdx) in angleTriples {
            let a = NormalizedPoints[aIdx]
            let b = NormalizedPoints[bIdx]
            let c = NormalizedPoints[cIdx]
            
            let angle = angleAtVertex(a, b, c)
            allDistances.append(round4(angle))
        }
        let anglesCount = allDistances.count - anglesStart
        
        // ----------------------------------------------------------------
        // Log summary
        // ----------------------------------------------------------------
        print("""
        📏 Pattern Vector Computed:
           Total elements: \(allDistances.count) [expected 363]
           - Reference (33-263):     1
           - Mandatory×Mandatory:    \(mandatoryCount) [expected 135]
           - Optional chain:         \(optionalChainCount) [expected 10]
           - Optional×Mandatory:     \(bipartiteCount) [expected 170]
           - Angles:                 \(anglesCount) [expected 47]
        """)
        
        // Sanity check
        if allDistances.count != 363 {
            print("⚠️ WARNING: Expected 363 elements, got \(allDistances.count)")
        }
        
        // ----------------------------------------------------------------
        // CONDITION CHECK with detailed logging
        // ----------------------------------------------------------------
        print("""
        🔍 Frame Collection Conditions:
           isFaceReal:      \(isFaceReal)
           ratioIsInRange:  \(ratioIsInRange)
           isHeadPoseStable: \(isHeadPoseStable())
           Pitch: \(Pitch), Yaw: \(Yaw), Roll: \(Roll)
           Ratio: \(irisDistanceRatio ?? -1)
        """)
        
        // LIVENESS GATE: Only store if ALL conditions pass
        if isFaceReal && ratioIsInRange && isHeadPoseStable() && allDistances.count != 0{
            AllFramesOptionalAndMandatoryDistance.append(allDistances)
            totalFramesCollected = AllFramesOptionalAndMandatoryDistance.count
            frameRecordedTrigger.toggle()
            
            print("""
            ✅ FRAME ACCEPTED & STORED:
               frameIndex (1-based) = \(totalFramesCollected)
               vector length        = \(allDistances.count)
               total stored frames  = \(AllFramesOptionalAndMandatoryDistance.count)
            """)
        } else {
            rejectedFrames += 1
            
            // Detailed rejection reason
            var reasons: [String] = []
            if !isFaceReal { reasons.append("SPOOF") }
            if !ratioIsInRange { reasons.append("DISTANCE") }
            if !isHeadPoseStable() { reasons.append("HEAD_POSE") }
            
            print("""
            ❌ FRAME REJECTED:
               Reasons: \(reasons.joined(separator: ", "))
               rejectedFrames = \(rejectedFrames)
               vector computed (len=\(allDistances.count)) but NOT stored
            """)
        }
    }
}

// MARK: - Float Extension
extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        return min(max(self, range.lowerBound), range.upperBound)
    }
}
