import Foundation
import simd
import CoreGraphics

// MARK: - Face Metrics (EAR, Angles, Bounding Box)
extension FaceManager {
    
    // MARK: - Eye Aspect Ratio (EAR)
    /// Helper function to calculate distance between two SIMD2 points
    @inline(__always)
    private func dist(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
        length(a - b)
    }
    
    /// Computes average Eye Aspect Ratio (EAR) from full 468-point mesh
    /// Lower EAR values indicate closed eyes, higher values indicate open eyes
    func earCalc(from landmarks: [SIMD2<Float>]) -> Float {
        guard landmarks.count > 387 else { return 0 }
        
        // LEFT eye: (160,144), (158,153) / (33,133)
        let A_left = dist(landmarks[160], landmarks[144])
        let B_left = dist(landmarks[158], landmarks[153])
        let C_left = dist(landmarks[33],  landmarks[133])
        guard C_left > 0 else { return 0 }
        let ear_left = (A_left + B_left) / (2.0 * C_left)
        
        // RIGHT eye: (385,380), (387,373) / (362,263)
        let A_right = dist(landmarks[385], landmarks[380])
        let B_right = dist(landmarks[387], landmarks[373])
        let C_right = dist(landmarks[362], landmarks[263])
        guard C_right > 0 else { return 0 }
        let ear_right = (A_right + B_right) / (2.0 * C_right)
        
        return (ear_left + ear_right) / 2.0
    }
    
    // MARK: - Head Pose Estimation (Pitch, Yaw, Roll)
    
    /// Calculates face orientation angles from nose tip and vertical line
    /// Assumes normalized coordinates (within unit circle)
    @inline(__always)
    func angleCalc(noseTip: (x: Float, y: Float),
                   verticalLine: (x: Float, y: Float)) -> (pitch: Float, yaw: Float, roll: Float) {
        
        let x = noseTip.x
        let y = noseTip.y
        
        // Calculate denominator for angle calculations
        let oneMinusR2 = max(0 as Float, 1 - (x * x + y * y))
        let den = sqrtf(oneMinusR2)
        
        // Use atan2 for stability
        let pitch = atan2f(y, den)
        let yaw   = atan2f(x, den)
        let roll  = atan2f(verticalLine.y, verticalLine.x)
        
        return (pitch, yaw, roll)
    }
    
    // Computes angles from normalized landmarks (indices 4, 33, 263)
    func computeAngles(from landmarks: [(x: Float, y: Float)]) -> (pitch: Float, yaw: Float, roll: Float)? {
        let needed = [4, 33, 263]
        guard needed.allSatisfy({ $0 < landmarks.count }) else { return nil }
        
        let nose = landmarks[4]
        let p33 = landmarks[33]
        let p263 = landmarks[263]
        
        // Vector from 263 → 33 (vertical line)
        let verticalLine = (x: p33.x - p263.x, y: p33.y - p263.y)
        
        return angleCalc(noseTip: nose, verticalLine: verticalLine)
    }
    
    /// Checks if head pose is stable (within ±0.1 radians for all angles)
    func isHeadPoseStable() -> Bool {
        let threshold: Float = 0.1
        return abs(Pitch) <= threshold &&
               abs(Yaw) <= threshold &&
               abs(Roll) <= threshold
    }
    
    // MARK: - Face Bounding Box & Iris Distance
    
    /// Calculates face bounding box and iris distance ratio for liveness detection
    /// Also calculates and publishes the target iris size for UI overlay
    func calculateFaceBoundingBox() {
        // Need intrinsics and enough landmarks
        guard let fx = cameraSpecManager.currentSpecs?.intrinsicMatrix?.columns.0.x,
              CalculationCoordinates.count > 477,
              !CameraFeedCoordinates.isEmpty else {
            irisDistanceRatio = nil
            faceBoundingBox = nil
            return
        }
        
        // Constants for iris distance calculation
        let dIrisMm: Float = 11.5      // Average iris diameter in mm
        let LTargetMm: Float = 305.0   // Target distance in mm
        
        // ✅ Calculate and store iris_target_px for UI overlay
        let irisTarget_px = fx * (dIrisMm / LTargetMm)
        self.irisTargetPx = irisTarget_px
        
        // Iris landmark indices
        let leftIdxA = 476
        let leftIdxB = 474
        let rightIdxA = 471
        let rightIdxB = 469
        
        // Validate indices
        guard leftIdxA < CalculationCoordinates.count,
              leftIdxB < CalculationCoordinates.count,
              rightIdxA < CalculationCoordinates.count,
              rightIdxB < CalculationCoordinates.count else {
            irisDistanceRatio = nil
            faceBoundingBox = nil
            return
        }
        
        // Calculate iris diameters
        let diameterLeft_px  = Helper.shared.calculateDistance(
            CalculationCoordinates[leftIdxA],
            CalculationCoordinates[leftIdxB]
        )
        let diameterRight_px = Helper.shared.calculateDistance(
            CalculationCoordinates[rightIdxA],
            CalculationCoordinates[rightIdxB]
        )
        
        print("🔘 Diameter of Left IRIS: \(diameterLeft_px)")
        print("🔘 Diameter of RIGHT IRIS: \(diameterRight_px)")
        
        let d_mean_px: Float = (diameterLeft_px + diameterRight_px) / 2.0
        guard irisTargetPx > 0 else {
            irisDistanceRatio = nil
            faceBoundingBox = nil
            return
        }
        
        // Calculate and publish ratio
        let ratio = d_mean_px / irisTargetPx
        irisDistanceRatio = ratio
        
        // ✅ Updated acceptance range to 0.95 - 1.05
        if ratio >= 0.95 && ratio <= 1.05 {
            self.ratioIsInRange = true
            print("✅ ACCEPT (ratio = \(ratio))")
        } else {
            self.ratioIsInRange = false
            print("❌ REJECT (ratio = \(ratio))")
        }
        
        // Calculate face bounding box using face oval landmarks
        var minX = Float.greatestFiniteMagnitude
        var minY = Float.greatestFiniteMagnitude
        var maxX = -Float.greatestFiniteMagnitude
        var maxY = -Float.greatestFiniteMagnitude
        
        for idx in faceOvalIndices {
            guard idx >= 0, idx < CameraFeedCoordinates.count else { continue }
            let p = CameraFeedCoordinates[idx]
            minX = min(minX, p.x)
            minY = min(minY, p.y)
            maxX = max(maxX, p.x)
            maxY = max(maxY, p.y)
        }
        
        if minX < maxX, minY < maxY {
            faceBoundingBox = CGRect(
                x: CGFloat(minX),
                y: CGFloat(minY),
                width: CGFloat(maxX - minX),
                height: CGFloat(maxY - minY)
            )
        } else {
            faceBoundingBox = nil
        }
    }
    
    func calculateTargetOvalDimensions() -> (width: Float, height: Float)? {
        guard let fx = cameraSpecManager.currentSpecs?.intrinsicMatrix?.columns.0.x else {
            return nil
        }
        
        let dIrisMm: Float = 11.5
        let LTargetMm: Float = 305.0
        let irisTarget_px = fx * (dIrisMm / LTargetMm)
        
        // ML team's formula
        let ovalWidth_px  = 9.0 * irisTarget_px
        let ovalHeight_px = 11.0 * irisTarget_px
        
        return (width: ovalWidth_px, height: ovalHeight_px)
    }
}
