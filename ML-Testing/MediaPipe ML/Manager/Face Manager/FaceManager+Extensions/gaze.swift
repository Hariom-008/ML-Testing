//
//  gaze.swift
//  ML-Testing
//
//  Created by Hari's Mac on 19.11.2025.
//

import Foundation
import Foundation

// MARK: - Gaze Tracking
extension FaceManager {
    
    // MARK: - Helper Functions
    
    /// Calculates mean of subset of coordinates by landmark indices
    func meanOfCalculationCoordinates(_ coords: [(x: Float, y: Float)],
                                      indices: [Int]) -> (x: Float, y: Float)? {
        guard !coords.isEmpty, !indices.isEmpty else { return nil }
        
        var sx: Float = 0
        var sy: Float = 0
        var cnt: Int = 0
        
        for i in indices {
            if i >= 0, i < coords.count {
                sx += coords[i].x
                sy += coords[i].y
                cnt += 1
            }
        }
        guard cnt > 0 else { return nil }
        let n = Float(cnt)
        return (x: sx / n, y: sy / n)
    }
    
    // MARK: - Iris & Eye Center Calculations
    
    /// Calculates actual iris positions relative to eye centers
    /// Returns normalized positions for left and right eyes
    func calculateActualLeftRight(
        from coords: [(x: Float, y: Float)]
    ) -> (left: (x: Float, y: Float)?, right: (x: Float, y: Float)?) {
        
        // Landmark indices for iris and eye centers
        let leftIrisIdx  = [468, 469, 470, 471, 472]
        let rightIrisIdx = [473, 474, 475, 476, 477]
        let leftEyeIdx   = [33, 7, 163, 144, 145, 153, 154, 155, 133, 173, 157, 158, 159, 160, 161, 246]
        let rightEyeIdx  = [362, 382, 381, 380, 374, 373, 390, 249, 263, 466, 388, 387, 386, 385, 384, 398]
        
        // Calculate center points
        let leftIrisCentre  = meanOfCalculationCoordinates(coords, indices: leftIrisIdx)
        let rightIrisCentre = meanOfCalculationCoordinates(coords, indices: rightIrisIdx)
        let leftEyeCentre   = meanOfCalculationCoordinates(coords, indices: leftEyeIdx)
        let rightEyeCentre  = meanOfCalculationCoordinates(coords, indices: rightEyeIdx)
        
        // Need both eye centers to compute scale
        guard let le = leftEyeCentre, let re = rightEyeCentre else {
            self.FaceScale = 0
            return (nil, nil)
        }
        
        // Calculate face scale (distance between eyes)
        let dx = re.x - le.x
        let dy = re.y - le.y
        var faceScale = sqrtf(dx * dx + dy * dy)
        if faceScale < 1e-6 { faceScale = 1e-6 }  // Avoid division by zero
        self.FaceScale = faceScale
        
        // Calculate iris positions relative to eye centers
        let actualLeft: (x: Float, y: Float)?
        if let li = leftIrisCentre {
            let dL = Helper.shared.sub(li, le)
            actualLeft = dL
        } else {
            actualLeft = nil
        }
        
        let actualRight: (x: Float, y: Float)?
        if let ri = rightIrisCentre {
            let dR = Helper.shared.sub(ri, re)
            actualRight = dR
        } else {
            actualRight = nil
        }
        
        return (actualLeft, actualRight)
    }
    
    // MARK: - Calibration Data Collection
    
    /// Appends actual iris positions to calibration lists
    /// Only collects data when face is real (liveness check)
    func AppendActualLeftRight() {
        // Gate: Only collect during calibration if face is real
        guard isFaceReal || !isCentreTracking else {
            if isCentreTracking {
                print("⚠️ Skipping calibration data - Spoof detected")
            }
            return
        }
        
        let (actualLeft, actualRight) = calculateActualLeftRight(from: CalculationCoordinates)
        guard let actualLeft = actualLeft, let actualRight = actualRight else {
            return
        }
        
        self.actualLeftList.append(actualLeft)
        self.actualRightList.append(actualRight)
        
        print("""
              🧮 Length of actualLeftList = \(actualLeftList.count)  && 
              Last Value: X = \(actualLeftList[actualLeftList.count-1].x), Y = \(actualLeftList[actualLeftList.count-1].y)
        """)
        print("""
            🧮 Length of actualRightList = \(actualRightList.count) &&
            Last Value: X = \(actualRightList[actualRightList.count-1].x), Y = \(actualRightList[actualRightList.count-1].y)
        """)
        print("✅ Actual Left and Right Are Appended in the List")
    }
    
    /// Calculates baseline center means from calibration data
    /// These means are used as reference points for gaze tracking
    func calculateCenterMeans() {
        guard !actualLeftList.isEmpty, !actualRightList.isEmpty else {
            print("⚠️ No values to calculate means for calibration")
            return
        }
        
        guard let meanLeft = Helper.shared.calculateMean(actualLeftList),
              let meanRight = Helper.shared.calculateMean(actualRightList) else {
            print("⚠️ Mean calculation failed")
            return
        }
        
        // Save the baseline
        actualLeftMean = meanLeft
        actualRightMean = meanRight
        
        print("✅ Calibration complete:")
        print("Left Mean: \(actualLeftMean)")
        print("Right Mean: \(actualRightMean)")
    }
    
    // MARK: - Gaze Vector Calculation
    
    /// Calculates gaze vector based on deviation from calibrated baseline
    /// Only active during movement tracking phase
    func calculateGazeVector() {
        guard isMovementTracking else { return }
        
        // Get current actual left/right from the frame
        let (maybeActualLeft, maybeActualRight) = calculateActualLeftRight(from: CalculationCoordinates)
        
        print("📏 Final Length of actualLeftList: \(actualLeftList.count)")
        print("📏 Final Length of actualRightList: \(actualRightList.count)")
        
        guard let actualLeft = maybeActualLeft,
              let actualRight = maybeActualRight else {
            print("⚠️ Could not unwrap actualLeft or actualRight")
            return
        }
        
        // Compute differences from the baseline means
        let diffLeft = Helper.shared.sub(actualLeft, actualLeftMean)
        let diffRight = Helper.shared.sub(actualRight, actualRightMean)
        
        // Average the deltas → gaze vector
        let sumDiff = Helper.shared.add(diffLeft, diffRight)
        GazeVector = Helper.shared.div(sumDiff, 2)
        
        print("🎯 GazeVector: \(GazeVector)")
    }
}
