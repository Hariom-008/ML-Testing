import Foundation
import SwiftUI

struct FaceOvalOverlay: View {
    @ObservedObject var faceManager: FaceManager
    
    var body: some View {
        Canvas { context, size in
            let points = faceManager.ScreenCoordinates
            
            guard !points.isEmpty else { return }
            
            // Draw only the face oval outline in blue
            drawFaceOval(context: context, points: points)
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
    
    private func drawFaceOval(context: GraphicsContext, points: [(x: CGFloat, y: CGFloat)]) {
        let faceOvalIndices: [Int] = [
            10, 338, 297, 332, 284, 251, 389, 356, 454, 323,
            361, 288, 397, 365, 379, 378, 400, 377, 152, 148,
            176, 149, 150, 136, 172, 58, 132, 93, 234, 127,
            162, 21, 54, 103, 67, 109
        ]
        
        // Ensure we have enough points
        guard points.count > faceOvalIndices.max() ?? 0 else { return }
        
        // Create path connecting all face oval points
        var path = Path()
        
        // Move to first point
        if let firstIdx = faceOvalIndices.first,
           firstIdx < points.count {
            let firstPoint = points[firstIdx]
            path.move(to: CGPoint(x: firstPoint.x, y: firstPoint.y))
        }
        
        // Draw lines to each subsequent point
        for idx in faceOvalIndices.dropFirst() {
            guard idx < points.count else { continue }
            let point = points[idx]
            path.addLine(to: CGPoint(x: point.x, y: point.y))
        }
        
        // Close the path by connecting back to the first point
        path.closeSubpath()
        
        // Stroke the path in blue with a thicker line
        context.stroke(
            path,
            with: faceManager.FaceOvalIsInTarget ? .color(.green) : .color(.blue),
            lineWidth: 2.0
        )
    }
}
