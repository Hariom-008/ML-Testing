//
//  SliceDistanceArray.swift
//  ML-Testing
//
//  Created by Hari's Mac on 21.11.2025.
//

import Foundation
extension FaceManager {
    
    /// Returns up to 20 frames, each trimmed to first 316 values
    func save316LengthDistanceArray() -> [[Float]] {
        // Require at least 20 frames collected
        guard AllFramesOptionalAndMandatoryDistance.count >= 20 else {
            print("⚠️ Not enough frames. Have \(AllFramesOptionalAndMandatoryDistance.count), need at least 20.")
            return []
        }
        
        // Take first 20 frames
        let first20Frames = Array(AllFramesOptionalAndMandatoryDistance.prefix(20))
        
        // For each frame, keep only first 316 values
        let trimmed = first20Frames.map { frame -> [Float] in
            Array(frame.prefix(316))
        }
        
        return trimmed
    }
    
    /// Prints the trimmed arrays (20 arrays × 316 values)
    func printTrimmedDistances() {
        let trimmed = save316LengthDistanceArray()
        
        guard !trimmed.isEmpty else {
            print("❌ No trimmed distances to print.")
            return
        }
        
        print("✅ Trimmed distances: \(trimmed.count) frames")
        
        for (frameIndex, frame) in trimmed.enumerated() {
           // print("—— Frame \(frameIndex + 1) — count: \(frame.count)")
            print(frame)   // prints the [Float] array
        }
    }
}
