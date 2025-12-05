//
//  IODGate.swift
//  ML-Testing
//
//  Created by Hari's Mac on 02.12.2025.
//

import Foundation
import CoreGraphics
import Combine

/// Handles IOD gating logic
final class IODGate: ObservableObject {
    @Published var iodPixels: CGFloat = 0.0
    @Published var isInRange: Bool = false

    // You can tweak these thresholds if needed
    var minIOD: CGFloat = 130.0
    var maxIOD: CGFloat = 160.0

    /// pixelLandmarks: array of 478 points in *pixel* space.
    /// index 33 = left eye outer, 263 = right eye outer.
    func updateIOD(pixelLandmarks: [CGPoint]) {
        guard pixelLandmarks.count > 263 else {
            iodPixels = 0
            isInRange = false
            return
        }

        let leftEyeOuter = pixelLandmarks[33]
        let rightEyeOuter = pixelLandmarks[263]

        let dx = rightEyeOuter.x - leftEyeOuter.x
        let dy = rightEyeOuter.y - leftEyeOuter.y

        let iod = sqrt(dx * dx + dy * dy)
        iodPixels = iod
        isInRange = iod >= minIOD && iod <= maxIOD
    }
}
