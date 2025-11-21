//
//  FaceBoundingOverlay.swift
//  ML-Testing
//
//  Created by Hari's Mac on 19.11.2025.
//

import Foundation
import SwiftUI

struct FaceBoundingBoxOverlay: View {
    let boundingBox: CGRect      // in image coordinates
    let imageSize: CGSize
    let screenSize: CGSize
    let isAccepted: Bool         // true → green, false → gray

    var body: some View {
        // Avoid division by zero
        let w = max(imageSize.width, 1)
        let h = max(imageSize.height, 1)

        // Simple linear scale (assumes preview fills the screen)
        let scaleX = screenSize.width  / w
        let scaleY = screenSize.height / h

        let rect = CGRect(
            x: boundingBox.origin.x * scaleX,
            y: boundingBox.origin.y * scaleY,
            width:  boundingBox.size.width  * scaleX,
            height: boundingBox.size.height * scaleY
        )

        print("DEBUG: Face overlay - rect: \(rect), accepted: \(isAccepted)")

        return Path { path in
            let top    = rect.minY
            let bottom = rect.maxY
            let midX   = rect.midX
            let midY   = rect.midY
            
            let width  = rect.width
            let height = rect.height

            print("DEBUG: Face dimensions - w:\(width) h:\(height)")

            // Simple circle - exactly as shown in screenshot
            let radius = min(width, height) / 2
            let centerX = midX
            let centerY = midY
            
            print("DEBUG: Drawing circle - radius: \(radius), center: (\(centerX), \(centerY))")
            
            path.addEllipse(in: CGRect(
                x: centerX - radius,
                y: centerY - radius,
                width: radius * 2,
                height: radius * 2
            ))
            
            print("DEBUG: Circle drawn")
        }
        .stroke(isAccepted ? Color.green : Color.gray, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        .animation(.easeInOut(duration: 0.2), value: isAccepted)
    }
}
