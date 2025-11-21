//
//  TargetOverlay.swift
//  ML-Testing
//
//  Created by Hari's Mac on 19.11.2025.
//

import Foundation
import SwiftUI

/// Fixed target oval overlay - shows where user should position their face
/// This oval is FIXED on screen and doesn't move with the detected face
struct FixedTargetOvalOverlay: View {
    let imageSize: CGSize          // Camera image size
    let screenSize: CGSize         // Screen size
    let irisDistanceRatio: Float?  // nil or the ratio value
    let faceManager: FaceManager   // To get target oval dimensions
    
    var body: some View {
        GeometryReader { geometry in
            if let dimensions = faceManager.calculateTargetOvalDimensions() {
                let ovalView = createOvalView(
                    ovalWidthPx: dimensions.width,
                    ovalHeightPx: dimensions.height,
                    in: geometry.size
                )
                
                ovalView
            }
        }
    }
    
    private func createOvalView(ovalWidthPx: Float, ovalHeightPx: Float, in size: CGSize) -> some View {
        // Avoid division by zero
        let imgW = max(imageSize.width, 1)
        let imgH = max(imageSize.height, 1)
        
        // Calculate scale from image coordinates to screen coordinates
        let scaleX = size.width / imgW
        let scaleY = size.height / imgH
        
        // Use the minimum scale to maintain aspect ratio
        let scale = min(scaleX, scaleY)
        
        // Convert oval dimensions from image pixels to screen points
        let ovalWidthScreen = CGFloat(ovalWidthPx) * scale
        let ovalHeightScreen = CGFloat(ovalHeightPx) * scale
        
        // Center the oval on screen
        let centerX = size.width / 2
        let centerY = size.height / 2
        
        // Determine if face is within acceptable range
        let isAccepted: Bool
        if let ratio = irisDistanceRatio {
            isAccepted = ratio >= 0.95 && ratio <= 1.05
        } else {
            isAccepted = false
        }
        
        let strokeColor = isAccepted ? Color.green : Color.gray.opacity(0.8)
        
        return Path { path in
            let rect = CGRect(
                x: centerX - ovalWidthScreen / 2,
                y: centerY - ovalHeightScreen / 2,
                width: ovalWidthScreen,
                height: ovalHeightScreen
            )
            
            path.addEllipse(in: rect)
            
            #if DEBUG
            print("📊 Target Oval Debug:")
            print("  - Image size: \(imageSize)")
            print("  - Screen size: \(size)")
            print("  - Scale: \(scale)")
            print("  - Oval (px): \(ovalWidthPx) × \(ovalHeightPx)")
            print("  - Oval (screen): \(ovalWidthScreen) × \(ovalHeightScreen)")
            print("  - Center: (\(centerX), \(centerY))")
            print("  - Ratio: \(irisDistanceRatio ?? -1)")
            print("  - Accepted: \(isAccepted)")
            #endif
        }
        .stroke(strokeColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
        .animation(.easeInOut(duration: 0.3), value: isAccepted)
    }
}

// MARK: - Optional: Debug overlay showing actual face detection
/// This is optional - shows the detected face bounding box for debugging
/// You can remove this in production
struct DetectedFaceDebugOverlay: View {
    let boundingBox: CGRect?
    let imageSize: CGSize
    let screenSize: CGSize
    
    var body: some View {
        if let box = boundingBox {
            GeometryReader { geometry in
                let rect = scaleRect(box, to: geometry.size)
                
                Path { path in
                    path.addRect(rect)
                }
                .stroke(Color.yellow.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [5, 5]))
            }
        }
    }
    
    private func scaleRect(_ rect: CGRect, to screenSize: CGSize) -> CGRect {
        let imgW = max(imageSize.width, 1)
        let imgH = max(imageSize.height, 1)
        
        let scaleX = screenSize.width / imgW
        let scaleY = screenSize.height / imgH
        
        return CGRect(
            x: rect.origin.x * scaleX,
            y: rect.origin.y * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        )
    }
}

// MARK: - Preview for SwiftUI Canvas
#if DEBUG
struct FixedTargetOvalOverlay_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black
            
            // Mock preview - you'll need to pass actual FaceManager instance
            FixedTargetOvalOverlay(
                imageSize: CGSize(width: 640, height: 480),
                screenSize: CGSize(width: 393, height: 852),
                irisDistanceRatio: 1.0,  // Accepted
                faceManager: FaceManager(cameraSpecManager: CameraSpecManager())
            )
        }
        .previewDisplayName("Accepted State")
        
        ZStack {
            Color.black
            
            FixedTargetOvalOverlay(
                imageSize: CGSize(width: 640, height: 480),
                screenSize: CGSize(width: 393, height: 852),
                irisDistanceRatio: 1.2,  // Too far
                faceManager: FaceManager(cameraSpecManager: CameraSpecManager())
            )
        }
        .previewDisplayName("Rejected State")
    }
}
#endif
