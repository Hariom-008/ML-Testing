//
//  Direction.swift
//  ML-Testing
//
//  Created by Hari's Mac on 28.11.2025.
//

import Foundation
import SwiftUI
 
extension FaceManager{
    // Calculate position offset for guidance
    func getPositionOffset() -> (x: CGFloat, y: CGFloat) {
        guard let currentCenter = getCurrentFaceCenter(),
              let targetCenter = getTargetFaceCenter() else {
            return (0, 0)
        }
        
        return (
            x: currentCenter.x - targetCenter.x,
            y: currentCenter.y - targetCenter.y
        )
    }

    private func getCurrentFaceCenter() -> CGPoint? {
        guard !ScreenCoordinates.isEmpty else { return nil }
        let sumX = ScreenCoordinates.reduce(0) { $0 + $1.x }
        let sumY = ScreenCoordinates.reduce(0) { $0 + $1.y }
        return CGPoint(
            x: sumX / CGFloat(ScreenCoordinates.count),
            y: sumY / CGFloat(ScreenCoordinates.count)
        )
    }

    private func getTargetFaceCenter() -> CGPoint? {
        guard !TransalatedScaledFaceOvalCoordinates.isEmpty else { return nil }
        let sumX = TransalatedScaledFaceOvalCoordinates.reduce(0) { $0 + $1.x }
        let sumY = TransalatedScaledFaceOvalCoordinates.reduce(0) { $0 + $1.y }
        return CGPoint(
            x: sumX / CGFloat(TransalatedScaledFaceOvalCoordinates.count),
            y: sumY / CGFloat(TransalatedScaledFaceOvalCoordinates.count)
        )
    }
}
