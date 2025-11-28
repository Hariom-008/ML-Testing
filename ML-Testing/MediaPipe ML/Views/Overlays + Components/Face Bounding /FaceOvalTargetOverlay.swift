import SwiftUI

struct TargetFaceOvalOverlay: View {
    @ObservedObject var faceManager: FaceManager
    
    var body: some View {
        Canvas { context, size in
            guard faceManager.TransalatedScaledFaceOvalCoordinates.count > 1 else { return }
            
            // Build the face oval path
            var path = Path()
            let points = faceManager.TransalatedScaledFaceOvalCoordinates
            
            // Start from first point
            path.move(to: CGPoint(x: points[0].x, y: points[0].y))
            
            // Connect each point in sequence
            for i in 1..<points.count {
                path.addLine(to: CGPoint(x: points[i].x, y: points[i].y))
            }
            
            // Close the path (to form a continuous oval)
            path.addLine(to: CGPoint(x: points[0].x, y: points[0].y))
            
            // Draw the path
            context.stroke(
                path,
                with: faceManager.FaceOvalIsInTarget ? .color(.green): .color(.pink.opacity(0.8)),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
