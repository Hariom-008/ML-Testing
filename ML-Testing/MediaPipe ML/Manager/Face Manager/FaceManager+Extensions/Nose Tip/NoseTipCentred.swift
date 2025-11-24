//
//  NoseTipCentred.swift
//  ML-Testing
//
//  Created by Hari's Mac on 24.11.2025.
//

import Foundation

extension FaceManager{
    // MARK: - Nose tip center check using pixel distance (JS parity)
//    func updateNoseTipCenterStatus(for screenSize: CGSize,
//                                   pixelRadius: CGFloat = 40.0) {
//        // Need landmark 4 (nose tip)
//        guard NormalizedPoints.count > 4 else {
//            isNoseTipCentered = false
//            return
//        }
//
//        let nose = NormalizedPoints[4]  // assumed 0–1 normalized from MediaPipe
//
//        // Screen center in pixels
//        let cx = screenSize.width  / 2.0
//        let cy = screenSize.height / 2.0
//
//        // Convert nose normalized to pixel coords (mirror JS: x * W, (1 - y) * H)
//        let nx = CGFloat(nose.x) * screenSize.width
//        let ny = (1.0 - CGFloat(nose.y)) * screenSize.height
//
//        let dx = nx - cx
//        let dy = ny - cy
//
//        // Correct Euclidean distance (JS version has a bug, but this is what you want)
//        let distPix = sqrt(dx * dx + dy * dy)
//
//        // Debug to see actual values
//        // print("nosePx=(\(nx), \(ny)) center=(\(cx), \(cy)) distPix=\(distPix)")
//
//        isNoseTipCentered = distPix <= pixelRadius
//    }
    func updateNoseTipCenterStatusFromCalcCoords(tolerance: Float = 0.2) {
        guard NormalizedPoints.count > 4 else {
            isNoseTipCentered = false
            return
        }
        let nose = NormalizedPoints[4]   // now assumed centered coords
        let insideX = abs(nose.x) <= tolerance
        let insideY = abs(nose.y) <= tolerance
        isNoseTipCentered = insideX && insideY
    }

}
