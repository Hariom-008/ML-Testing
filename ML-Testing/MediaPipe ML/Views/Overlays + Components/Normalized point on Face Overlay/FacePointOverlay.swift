//
//  FacePointOverlay.swift
//  ML-Testing
//
//  Created by Hari's Mac on 27.11.2025.
//

import Foundation
import SwiftUI

struct FacePointsOverlay: View {
    @ObservedObject var faceManager: FaceManager
    
    // Radius of each landmark dot
    private let pointRadius: CGFloat = 1.2
    
    var body: some View {
        Canvas { context, size in
            // ✅ Use ScreenCoordinates instead of CameraFeedCoordinates
            let points = faceManager.ScreenCoordinates
            
            guard !points.isEmpty else { return }
            
            for p in points {
                let rect = CGRect(
                    x: p.x - pointRadius,
                    y: p.y - pointRadius,
                    width: pointRadius * 2,
                    height: pointRadius * 2
                )
                
                context.fill(
                    Path(ellipseIn: rect),
                    with: .color(.green)
                )
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}
