import AVFoundation
import UIKit
import MediaPipeTasksVision
import Combine
import simd
import Foundation
import SwiftUI
import Accelerate


extension FaceManager{
    
    func CalculateFeatureVector(){
        // ----- Load A and b -----
        let A = loadCSV(name: "A")    // (20 × 101)
        let A_T = transpose(A)        // (101 × 20)
        let b = loadCSV(name: "b")    // (20)
        
        // ----- Multiply full feature matrix -----
        let projected = multiplyMatrix(FeatureVectorBeforePCAAndLDA, with: A_T)   // (N × 20)
        
        // ----- Add bias -----
        let finalMatrix = addBiasMatrix(projected, b: b)           // (N × 20)
        if isFaceReal && isHeadPoseStable() && ratioIsInRange{
            FeatureVector += finalMatrix
            print("➕ Added new value to feature Vector: \(FeatureVector)")
            print("✅Feature Vectore Frame Count: \(FeatureVector.count)")
        }else if !isFaceReal || !isHeadPoseStable() || !ratioIsInRange{
            print("❌ Not Added to feature Vector ,isFaceReal:\(isFaceReal) isHeadPoseStable:\(isHeadPoseStable()) ratioIsInRange:\(ratioIsInRange)")
        }
    }
    
    func CalculateFeatureVectorBeforeMultiplication(){
        let distances = computeNormalizedDistances(from: self.NormalizedPoints)
        let curvatures = computeCurvatures(from: self.NormalizedPoints)
        let angles = computeAnglesArray(from: self.NormalizedPoints)
        
        let raw = distances + curvatures + angles   // (101)
        rawFeatures.append(raw)

        // ----- Normalization -----
        let mean = computeScalarMean(raw)
        let std = computeScalarStd(raw, mean: mean)
        let fv = raw.map { ($0 - mean) / std }
        
        // We will get a matrix of FeatureVectorBeforePCDAndLDA(N,101)
        FeatureVectorBeforePCAAndLDA.append(fv)
    }
    
    func computeScalarMean(_ vector: [Float]) -> Float {
        guard !vector.isEmpty else { return 0 }
        let sum = vector.reduce(0, +)
        return sum / Float(vector.count)
    }
    
    func computeScalarStd(_ vector: [Float], mean: Float) -> Float {
        guard !vector.isEmpty else { return 1 }
        
        var variance: Float = 0
        let n = Float(vector.count)
        
        for v in vector {
            let diff = v - mean
            variance += diff * diff
        }
        variance /= n
        
        let std = sqrt(variance)
        return std < 1e-8 ? 1.0 : std   // same as ML team
    }
    
    func standardize(raw: [Float]) -> [Float] {
        let mean = computeScalarMean(raw)
        let std  = computeScalarStd(raw, mean: mean)
        
        return raw.map { ($0 - mean) / std }
    }
    
    func multiplyMatrix(_ fv: [[Float]], with A_T: [[Float]]) -> [[Float]] {
        // fv shape: N × 101
        // A_T shape: 101 × 20
        
        let N = fv.count
        let rowsA = A_T.count       // 101
        let colsA = A_T[0].count    // 20
        
        // Safety check
        guard fv.first?.count == rowsA else {
            print("❌ Dimension mismatch: fv columns \(fv.first?.count ?? -1), A_T rows \(rowsA)")
            return []
        }
        
        // Output matrix N × 20
        var result = Array(
            repeating: Array(repeating: Float(0), count: colsA),
            count: N
        )
        
        for i in 0..<N {           // for each frame
            for j in 0..<colsA {    // for each output dimension
                var sum: Float = 0.0
                for k in 0..<rowsA {  // dot product
                    sum += fv[i][k] * A_T[k][j]
                }
                result[i][j] = sum
            }
        }
        
        return result
    }


    func loadCSV(name: String) -> [[Float]] {
        guard let url = Bundle.main.url(forResource: name, withExtension: "csv") else{
            print("❌ CSV not found")
            return []
        }
        
        guard let content = try? String(contentsOf: url) else {
            print("❌ Cannot read CSV")
            return []
        }
        
        var matrix: [[Float]] = []
        
        let rows = content.components(separatedBy: .newlines)
        
        for row in rows {
            let trimmed = row.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            
            let values = trimmed.split(separator: ",").compactMap { Float($0) }
            matrix.append(values)
        }
        
        return matrix
    }
    
    func transpose(_ m: [[Float]]) -> [[Float]] {
        guard !m.isEmpty else { return [] }
        
        let rows = m.count
        let cols = m[0].count
        
        var t = Array(repeating: Array(repeating: Float(0), count: rows), count: cols)
        
        for r in 0..<rows {
            for c in 0..<cols {
                t[c][r] = m[r][c]
            }
        }
        
        return t
    }
    
    func addBiasMatrix(_ M: [[Float]], b: [[Float]]) -> [[Float]]{
        let bias = b.flatMap { $0 }    // flatten to [20]
        
        let N = M.count
        let cols = M[0].count          // 20
        
        guard cols == bias.count else {
            print("❌ Bias dimension mismatch M_cols=\(cols) b=\(bias.count)")
            return M
        }
        
        var result = M
        for i in 0..<N {
            for j in 0..<cols {
                result[i][j] += bias[j]
            }
        }
        return result
    }

}
// MARK: - Distance Extraction Extension
extension FaceManager {
    /// Compute normalized distances for all keypoint_pair_sets.
    /// - Parameter landmarks: Array of (x,y) normalized points from MediaPipe (size 478).
    /// - Returns: Flat distance vector [Float], normalized by dist(263, 33).
    func computeNormalizedDistances(from landmarks: [(x: Float, y: Float)]) -> [Float] {
        guard landmarks.count > 330 else { return [] }
        
        func euclidean(_ p1: (x: Float, y: Float), _ p2: (x: Float, y: Float)) -> Float {
            let dx = p1.x - p2.x
            let dy = p1.y - p2.y
            return sqrt(dx*dx + dy*dy)
        }
        
        // ----------------------------------------------------
        // 1️⃣ Reference distance between 263 and 33
        // ----------------------------------------------------
        let refP1 = landmarks[263]
        let refP2 = landmarks[33]
        
        var refDist = euclidean(refP1, refP2)
        if refDist < 1e-8 { refDist = 1.0 }   // safe fallback
        
        // ----------------------------------------------------
        // 2️⃣ Compute normalized distances
        // ----------------------------------------------------
        var distances: [Float] = []
        distances.reserveCapacity(300)  // minor perf optimization
        
        for group in keypoint_pair_sets {
            for (i, j) in group {
                let p1 = landmarks[i]
                let p2 = landmarks[j]
                
                var d = euclidean(p1, p2) / refDist
                d = Float((d * 10000).rounded() / 10000)    // round to 4 decimals
                distances.append(d)
            }
        }
        
        return distances
    }

}

// MARK: - Curvature Extraction Extension
extension FaceManager {
    /// Compute curvature for 3 points (Swift version of ML team formula)
    private func triangleSignedCurvature(_ p1: SIMD2<Float>,
                                         _ p2: SIMD2<Float>,
                                         _ p3: SIMD2<Float>,
                                         eps: Float = 1e-8) -> Float {
        
        // Side lengths
        let l12 = simd_distance(p1, p2)
        let l23 = simd_distance(p2, p3)
        let l31 = simd_distance(p3, p1)
        
        // Degenerate triangle
        if l12 < eps || l23 < eps || l31 < eps {
            return 0.0
        }
        
        // Area using cross product from p1
        let v12 = p2 - p1
        let v13 = p3 - p1
        let crossArea = v12.x * v13.y - v12.y * v13.x
        let A = 0.5 * abs(crossArea)
        
        if A < eps {
            return 0.0   // collinear
        }
        
        // Circumradius
        let R = (l12 * l23 * l31) / (4.0 * A)
        if R < eps { return 0.0 }
        
        let k = 1.0 / R
        
        // Signed curvature using cross at middle point p2
        let v1 = p1 - p2
        let v2 = p3 - p2
        let crossMid = v1.x * v2.y - v1.y * v2.x
        let sign: Float = crossMid >= 0 ? 1.0 : -1.0
        
        return k * sign
    }
    
    
    /// Compute curvature array for all curvature_sets.
    /// - Parameter landmarks: normalized (x,y) MediaPipe points.
    /// - Returns: `[Float]` curvature values rounded to 4 decimals.
    func computeCurvatures(from landmarks: [(x: Float, y: Float)]) -> [Float] {
        guard landmarks.count > 450 else { return [] }
        
        let pts = landmarks.asSIMD2
        var curvatures: [Float] = []
        curvatures.reserveCapacity(200)
        
        for tripleGroup in curvature_sets {
            for (i, j, k) in tripleGroup {
                let p1 = pts[i]
                let p2 = pts[j]
                let p3 = pts[k]
                
                let c = triangleSignedCurvature(p1, p2, p3)
                let rounded = Float((c * 10000).rounded() / 10000)  // 4 decimals
                curvatures.append(rounded)
            }
        }
        
        return curvatures
    }
}
// MARK: - Angle Extraction Extension
extension FaceManager {
    
    /// Swift version of ML team's signed angle function
    private func signedAngle(_ p1: SIMD2<Float>,
                             _ p2: SIMD2<Float>,
                             _ p3: SIMD2<Float>,
                             eps: Float = 1e-8) -> Float {
        
        var v1 = p1 - p2   // P1 -> P2 direction
        var v2 = p3 - p2   // P3 -> P2 direction
        
        let norm1 = simd_length(v1)
        let norm2 = simd_length(v2)
        
        if norm1 < eps || norm2 < eps {
            return 0.0   // degenerate
        }
        
        v1 /= norm1
        v2 /= norm2
        
        let dot: Float = v1.x * v2.x + v1.y * v2.y
        let cross: Float = v1.x * v2.y - v1.y * v2.x
        
        // signed angle in radians
        let angle = atan2(cross, dot)
        return angle
    }
    
    
    /// Compute angles for all angle_sets.
    /// Matches Python exactly: angle = atan2(cross, dot)
    func computeAnglesArray(from landmarks: [(x: Float, y: Float)]) -> [Float] {
        guard landmarks.count > 330 else { return [] }
        
        let pts = landmarks.asSIMD2
        var angleList: [Float] = []
        angleList.reserveCapacity(100)
        
        for tripleGroup in angle_sets {
            for (i, j, k) in tripleGroup {
                let p1 = pts[i]
                let p2 = pts[j]
                let p3 = pts[k]
                
                let a = signedAngle(p1, p2, p3)
                let rounded = Float((a * 10000).rounded() / 10000)
                angleList.append(rounded)
            }
        }
        
        return angleList
    }
    
}
