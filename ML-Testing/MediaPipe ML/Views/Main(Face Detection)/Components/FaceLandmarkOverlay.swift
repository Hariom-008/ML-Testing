//
//  FaceLandmarkOverlay.swift
//  ML-Testing
//
//  Created by Hari's Mac on 05.11.2025.
//

import Foundation
import SwiftUI

// MARK: - FaceLandmarksOverlay
struct FaceLandmarksOverlay: View {
    let landmarks: [(x: Float, y: Float)]
    let imageSize: CGSize
    
    var body: some View {
        GeometryReader { geometry in
            let scaleX: CGFloat = geometry.size.width / imageSize.width
            let scaleY: CGFloat = geometry.size.height / imageSize.height
            
            ZStack {
                ForEach(Array(landmarks.enumerated()), id: \.offset) { _, lm in
                    Circle()
                        .fill(Color.green)
                        .frame(width: 3.5, height: 3.5)
                        .position(
                            x: CGFloat(lm.x) * scaleX,
                            y: CGFloat(lm.y) * scaleY
                        )
                }
            }
        }
    }
}
