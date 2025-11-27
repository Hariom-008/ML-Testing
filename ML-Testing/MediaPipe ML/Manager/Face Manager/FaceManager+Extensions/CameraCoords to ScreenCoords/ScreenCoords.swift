//
//  ScreenCoords.swift
//  ML-Testing
//
//  Created by Hari's Mac on 27.11.2025.
//

import Foundation
internal import AVFoundation
import CoreGraphics

extension FaceManager {
    func cameraPointToScreenPoint(
        x: CGFloat,
        y: CGFloat,
        cameraWidth: CGFloat,
        cameraHeight: CGFloat
    ) -> CGPoint {
        
        guard let previewLayer = self.previewLayer else {
            return .zero
        }

        // 1. Normalized camera coords (MediaPipe coordinates)
        let normalizedX = x / cameraWidth
        let normalizedY = y / cameraHeight
        
        // 2. MediaPipe origin is top-left; AVFoundation previewLayer works the same
        let metadataPoint = CGPoint(x: normalizedX, y: normalizedY)
        
        // 3. Convert using AVFoundation’s built-in mapping
        // Handles:
        // - aspectFill
        // - cropping
        // - scaling
        // - mirroring (front camera)
        let screenPoint = previewLayer.layerPointConverted(fromCaptureDevicePoint: metadataPoint)
        
        return screenPoint
    }
}
