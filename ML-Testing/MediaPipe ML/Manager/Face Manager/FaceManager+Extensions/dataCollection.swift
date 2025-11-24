//
//  dataCollection.swift
//  ML-Testing
//
//  Created by Hari's Mac on 19.11.2025.
//

import Foundation
import Foundation

// MARK: - Data Collection & Management
extension FaceManager {
    
    /// Resets all collected data and tracking states for a new user
    /// Clears calibration data, collected frames, and resets all flags
    func resetForNewUser() {
        rawFeatures.removeAll()
        
        totalFramesCollected = 0
        
        // Clear calibration data
        actualLeftList.removeAll()
        actualRightList.removeAll()
        rejectedFrames = 0
        
        // Reset tracking states
        isCentreTracking = false
        isMovementTracking = false
        
        // Reset upload states
        uploadSuccess = false
        uploadError = nil
        isUploadingPattern = false
        
        // Reset liveness
        isFaceReal = false

        hasEnteredPhoneNumber = false
        
        print("🔄 Reset complete - ready for new user")
    }
    
    // MARK: - Data Export Helpers
    
    /// Returns the current collected 316-dim pattern data
    /// Each element is a frame containing 316 distance measurements
    /// 
//    func getCollectedPatternData() -> [[Float]] {
//        return AllFramesOptionalAndMandatoryDistance
//    }
    
    /// Returns the number of frames collected that passed liveness checks
    func getValidFrameCount() -> Int {
        return totalFramesCollected
    }
    
    /// Returns the number of frames rejected due to liveness checks
    func getRejectedFrameCount() -> Int {
        return rejectedFrames
    }
    
    /// Returns calibration data (mean iris positions)
    func getCalibrationData() -> (leftMean: (x: Float, y: Float), rightMean: (x: Float, y: Float)) {
        return (actualLeftMean, actualRightMean)
    }
    
    // MARK: - Validation Helpers
    
    /// Checks if enough calibration data has been collected
    func hasEnoughCalibrationData(minimumSamples: Int = 30) -> Bool {
        return actualLeftList.count >= minimumSamples && actualRightList.count >= minimumSamples
    }
    
    /// Checks if enough pattern frames have been collected
    func hasEnoughPatternFrames(minimumFrames: Int = 50) -> Bool {
        return totalFramesCollected >= minimumFrames
    }
    
    /// Returns collection progress as a percentage (0.0 to 1.0)
    func getCollectionProgress(targetFrames: Int = 100) -> Float {
        guard targetFrames > 0 else { return 0.0 }
        return min(Float(totalFramesCollected) / Float(targetFrames), 1.0)
    }
    
    /// Returns calibration progress as a percentage (0.0 to 1.0)
    func getCalibrationProgress(targetSamples: Int = 30) -> Float {
        guard targetSamples > 0 else { return 0.0 }
        let leftProgress = Float(actualLeftList.count) / Float(targetSamples)
        let rightProgress = Float(actualRightList.count) / Float(targetSamples)
        return min((leftProgress + rightProgress) / 2.0, 1.0)
    }
}
