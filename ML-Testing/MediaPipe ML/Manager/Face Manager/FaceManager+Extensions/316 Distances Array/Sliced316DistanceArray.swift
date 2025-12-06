//
//  SliceDistanceArray.swift
//  ML-Testing
//
//  Created by Hari's Mac on 21.11.2025.
//
import Foundation

extension FaceManager {
    
    /// Returns up to 80 frames, each trimmed to first 316 values
    func save316LengthDistanceArray() -> [[Float]] {
        // Require at least 80 frames collected
        guard AllFramesOptionalAndMandatoryDistance.count >= 80 else {
            print("⚠️ Not enough frames. Have \(AllFramesOptionalAndMandatoryDistance.count), need at least 80.")
            return []
        }
        
        // Take first 80 frames
        let first80Frames = Array(AllFramesOptionalAndMandatoryDistance.prefix(80))
        
        // For each frame, keep only first 316 values
        let trimmed = first80Frames.map { frame -> [Float] in
            Array(frame.prefix(316))
        }
        
        return trimmed
    }
    func VerifyFrameDistanceArray() -> [[Float]] {
        // Require at least 80 frames collected
        guard AllFramesOptionalAndMandatoryDistance.count >= 10 else {
            print("⚠️ Not enough frames. Have \(AllFramesOptionalAndMandatoryDistance.count), need at least 80.")
            return []
        }
        
        // Take first 10 frames
        let first10Frames = Array(AllFramesOptionalAndMandatoryDistance.prefix(10))
        
        // For each frame, keep only first 316 values
        let trimmed = first10Frames.map { frame -> [Float] in
            Array(frame.prefix(316))
        }
        
        return trimmed
    }
}
