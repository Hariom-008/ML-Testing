import SwiftUI

struct FaceOvalTargetOverlay: View {
    let centralOvalPoints: [CGPoint]?
    let userFacePoints: [(x: CGFloat, y: CGFloat)]
    let isFaceMatching: Bool
    
    var body: some View {
        Canvas { context, size in
            // Draw the FIXED central target oval (only when it exists)
            if let targetPoints = centralOvalPoints, !targetPoints.isEmpty {
                drawTargetOval(context: context, points: targetPoints)
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
    
    private func drawTargetOval(context: GraphicsContext, points: [CGPoint]) {
        var path = Path()
        
        guard let firstPoint = points.first else { return }
        path.move(to: firstPoint)
        
        // Connect all points
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        
        // Close the path
        path.closeSubpath()
        
        // Color based on matching status
        let targetColor: Color = isFaceMatching ? .green : .red
        
        // Draw the target oval with stroke
        context.stroke(
            path,
            with: .color(targetColor.opacity(0.8)),
            style: StrokeStyle(
                lineWidth: 4.0,
                lineCap: .round,
                lineJoin: .round
            )
        )
        
        // Optional: Add subtle fill
        context.fill(
            path,
            with: .color(targetColor.opacity(0.15))
        )
    }
}
