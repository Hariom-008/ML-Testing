import SwiftUI

struct FrameCollectionProgressView: View {
    @ObservedObject var faceManager: FaceManager
    let targetFrames: Int = 30
    
    @State private var rotationAngle: Double = 0
    @State private var particlePhase: CGFloat = 0
    
    var body: some View {
        VStack(spacing: 10) {
            // Circular progress with particles
            ZStack {
                // Outer glow ring
                Circle()
                    .stroke(progressColor.opacity(0.2), lineWidth: 8)
                    .frame(width: 80, height: 80)
                    .blur(radius: 4)
                
                // Background track
                Circle()
                    .stroke(
                        .white.opacity(0.15),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .frame(width: 70, height: 70)
                
                // Progress ring
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        AngularGradient(
                            colors: [
                                progressColor,
                                progressColor.opacity(0.7),
                                progressColor,
                            ],
                            center: .center,
                            startAngle: .degrees(0),
                            endAngle: .degrees(360)
                        ),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .frame(width: 70, height: 70)
                    .rotationEffect(.degrees(-90))
                    .rotationEffect(.degrees(rotationAngle))
                    .shadow(color: progressColor.opacity(0.5), radius: 8)
                    .animation(.spring(response: 0.6, dampingFraction: 0.8), value: progress)
                
                // Center content
                VStack(spacing: 2) {
                    Text("\(faceManager.totalFramesCollected)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, .white.opacity(0.9)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    
                    Text("/ \(targetFrames)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .onAppear {
                withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                    rotationAngle = 360
                }
            }
            
            // Status badge
            HStack(spacing: 6) {
                Circle()
                    .fill(progressColor)
                    .frame(width: 6, height: 6)
                    .shadow(color: progressColor, radius: 4)
                
                Text(statusText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                progressColor.opacity(0.3),
                                lineWidth: 1
                            )
                    )
            )
        }
        .padding(16)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [progressColor.opacity(0.4), progressColor.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            }
        )
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
    }
    
    private var progress: CGFloat {
        min(CGFloat(faceManager.totalFramesCollected) / CGFloat(targetFrames), 1.0)
    }
    
    private var progressColor: Color {
        if progress < 0.33 {
            return .orange
        } else if progress < 0.67 {
            return .yellow
        } else if progress < 1.0 {
            return .cyan
        } else {
            return .green
        }
    }
    
    private var statusText: String {
        if faceManager.totalFramesCollected == 0 {
            return "Ready"
        } else if faceManager.totalFramesCollected < targetFrames {
            return "Capturing"
        } else {
            return "Complete"
        }
    }
}
