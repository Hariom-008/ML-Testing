//
//  FaceManager+CentralOval.swift
//  ML-Testing
//
//  Integration of CentralOvalManager with FaceManager
//

import Foundation
import CoreGraphics
import SwiftUI

//extension FaceManager {
//    // Add to FaceManager class
//
//    func updateCentralOval(with ovalManager: CentralOvalManager, screenSize: CGSize) {
//        // Pass ALL screen coordinates to the manager
//        guard !ScreenCoordinates.isEmpty else { return }
//        
//        // Calculate average iris width
//        let leftIrisWidth = calculateIrisWidth(isLeft: true)
//        let rightIrisWidth = calculateIrisWidth(isLeft: false)
//        let avgIrisWidth = (leftIrisWidth + rightIrisWidth) / 2.0
//        
//        // Update buffer with all points
//        ovalManager.updateBuffer(
//            allScreenPoints: ScreenCoordinates,
//            currentIrisWidth: avgIrisWidth,
//            screenSize: screenSize
//        )
//        
//        // Check if current face matches the target
//        ovalManager.checkFaceMatch(allScreenPoints: ScreenCoordinates)
//    }
//
//    private func calculateIrisWidth(isLeft: Bool) -> CGFloat {
//        // Use eye corner landmarks to estimate iris width
//        let indices = isLeft ? [33, 133] : [362, 263]
//        guard indices.allSatisfy({ $0 < ScreenCoordinates.count }) else { return 50.0 }
//        
//        let p1 = ScreenCoordinates[indices[0]]
//        let p2 = ScreenCoordinates[indices[1]]
//        let dx = p1.x - p2.x
//        let dy = p1.y - p2.y
//        return sqrt(dx * dx + dy * dy)
//    }
//}
