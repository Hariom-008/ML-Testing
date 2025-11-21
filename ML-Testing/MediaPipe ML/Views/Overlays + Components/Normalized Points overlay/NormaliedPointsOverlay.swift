import SwiftUI

struct NormalizedPointsOverlay: View {
    let points: [(x: Float, y: Float)]
    var pointSize: CGFloat = 3.0
    var insetRatio: CGFloat = 0.12
    var smoothingAlpha: CGFloat = 0.25 

    @State private var smoothScale: CGFloat = 1.0

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width
            let H = geo.size.height
            let center = CGPoint(x: W * 0.5, y: H * 0.5)

            // rMax of current points in normalized space
            let rMax: CGFloat = {
                guard !points.isEmpty else { return 1 }
                var m: Float = 0
                for p in points {
                    let r2 = p.x*p.x + p.y*p.y
                    if r2 > m { m = r2 }
                }
                return CGFloat(sqrt(max(0, m)))
            }()

            // drawable radius and target scale to keep all points in frame
            let halfMinSide = min(W, H) * 0.5
            let drawableRadius = halfMinSide * (1.0 - insetRatio)
            let targetScale = drawableRadius / max(rMax, 0.001)

            ZStack {
                Color.black

                // boundary circle (visual padding)
                Circle()
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    .frame(width: drawableRadius * 2, height: drawableRadius * 2)
                    .position(center)

                // axes
                Path { p in
                    p.move(to: CGPoint(x: 0, y: center.y))
                    p.addLine(to: CGPoint(x: W, y: center.y))
                    p.move(to: CGPoint(x: center.x, y: 0))
                    p.addLine(to: CGPoint(x: center.x, y: H))
                }
                .stroke(Color.white.opacity(0.12), lineWidth: 1)

                // points
                Canvas { context, _ in
                    guard !points.isEmpty else { return }
                    let scale = smoothScale
                    for p in points {
                        let vx = center.x + CGFloat(p.x) * scale
                        let vy = center.y - CGFloat(p.y) * scale  // Y-up
                        let rect = CGRect(x: vx - pointSize * 0.5,
                                          y: vy - pointSize * 0.5,
                                          width: pointSize,
                                          height: pointSize)
                        context.fill(Path(ellipseIn: rect), with: .color(.green))
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            // initialize once when size appears
            .onAppear {
                smoothScale = targetScale
            }
            // EMA smoothing whenever the targetScale changes (points/size change)
            .onChange(of: targetScale) { newValue in
                let a = smoothingAlpha
                smoothScale = smoothScale * (1 - a) + newValue * a
            }
        }
    }
}
