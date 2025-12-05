import SwiftUI

struct DirectionalGuidanceOverlay: View {
    @ObservedObject var faceManager: FaceManager
    
    @State private var pulseScale: CGFloat = 1.0
    @State private var arrowOffset: CGFloat = 0
    @State private var successScale: CGFloat = 0.8
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Main guidance layer (distance guidance only when not in range)
                if !allConditionsMet {
                    ambientGuidanceLayer
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
                
                // Arrow guidance inside oval (only when distance is correct)
                if faceManager.ratioIsInRange && !allConditionsMet {
                    arrowGuidanceInsideOval(in: geometry.size)
                        .transition(.opacity)
                }
                
                // Success state
                if allConditionsMet {
                    VStack{
                        Spacer()
                        HStack{
                            Spacer()
                            successCelebration
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.85).combined(with: .opacity),
                                    removal: .opacity
                                ))
                            Spacer()
                        }
                        Spacer()
                    }
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: allConditionsMet)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: faceManager.ratioIsInRange)
        }
        .allowsHitTesting(false)
    }
    
    // MARK: - Computed Properties
    
    private var allConditionsMet: Bool {
        faceManager.isHeadPoseStable() &&
        faceManager.isFaceReal &&
        faceManager.FaceOvalIsInTarget &&
        faceManager.ratioIsInRange &&
        faceManager.isNoseTipCentered
    }
    
    private var positionGuidance: PositionGuidance {
        guard !faceManager.ScreenCoordinates.isEmpty,
              !faceManager.TransalatedScaledFaceOvalCoordinates.isEmpty else {
            return PositionGuidance()
        }
        
        let actualCenter = calculateCenter(from: faceManager.ScreenCoordinates)
        let targetCenter = calculateCenter(from: faceManager.TransalatedScaledFaceOvalCoordinates)
        
        let deltaX = actualCenter.x - targetCenter.x
        let deltaY = actualCenter.y - targetCenter.y
        
        let threshold: CGFloat = 20
        
        var guidance = PositionGuidance()
        
        // Horizontal guidance
        if deltaX > threshold {
            guidance.horizontal = .left
            guidance.horizontalIntensity = min(abs(deltaX) / 80, 1.0)
        } else if deltaX < -threshold {
            guidance.horizontal = .right
            guidance.horizontalIntensity = min(abs(deltaX) / 80, 1.0)
        }
        
        // Vertical guidance
        if deltaY > threshold {
            guidance.vertical = .up
            guidance.verticalIntensity = min(abs(deltaY) / 80, 1.0)
        } else if deltaY < -threshold {
            guidance.vertical = .down
            guidance.verticalIntensity = min(abs(deltaY) / 80, 1.0)
        }
        
        // Distance guidance
        if let ratio = faceManager.irisDistanceRatio {
            if ratio < 0.95 {
                guidance.distance = .closer
                guidance.distanceIntensity = CGFloat(min((0.95 - ratio) / 0.15, 1.0))
            } else if ratio > 1.05 {
                guidance.distance = .farther
                guidance.distanceIntensity = CGFloat(min((ratio - 1.05) / 0.15, 1.0))
            }
        }
        
        return guidance
    }
    
    private func calculateCenter(from points: [(x: CGFloat, y: CGFloat)]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        let sumX = points.reduce(0.0) { $0 + $1.x }
        let sumY = points.reduce(0.0) { $0 + $1.y }
        return CGPoint(x: sumX / CGFloat(points.count), y: sumY / CGFloat(points.count))
    }
    
    // MARK: - Arrow Guidance Inside Oval
    
    private func arrowGuidanceInsideOval(in size: CGSize) -> some View {
        let guidance = positionGuidance
        let targetCenter = calculateCenter(from: faceManager.TransalatedScaledFaceOvalCoordinates)
        
        return ZStack {
            // Left arrow
            if guidance.horizontal == .left {
                AsyncImage(url: URL(string: "https://res.cloudinary.com/da2cxcqup/image/upload/v1764256539/rollleft_jm0ady.png")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                } placeholder: {
                    ProgressView()
                }
                .position(x: targetCenter.x - 80, y: targetCenter.y)
                .modifier(DirectionalPulseModifier(intensity: guidance.horizontalIntensity, direction: .left))
            }
            
            // Right arrow
            if guidance.horizontal == .right {
                AsyncImage(url: URL(string: "https://res.cloudinary.com/da2cxcqup/image/upload/v1764256007/rollright_arpuqd.png")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                } placeholder: {
                    ProgressView()
                }
                .position(x: targetCenter.x + 80, y: targetCenter.y)
                .modifier(DirectionalPulseModifier(intensity: guidance.horizontalIntensity, direction: .right))
            }
            
            // Up arrow
            if guidance.vertical == .up {
                AsyncImage(url: URL(string: "https://res.cloudinary.com/da2cxcqup/image/upload/v1764253847/up_xeoewe.png")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                } placeholder: {
                    ProgressView()
                }
                .position(x: targetCenter.x, y: targetCenter.y - 100)
                .modifier(DirectionalPulseModifier(intensity: guidance.verticalIntensity, direction: .up))
            }
            
            // Down arrow
            if guidance.vertical == .down {
                AsyncImage(url: URL(string: "https://res.cloudinary.com/da2cxcqup/image/upload/v1764253847/down_ijhlr4.png")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                } placeholder: {
                    ProgressView()
                }
                .position(x: targetCenter.x, y: targetCenter.y + 100)
                .modifier(DirectionalPulseModifier(intensity: guidance.verticalIntensity, direction: .down))
            }
        }
    }
    
    // MARK: - Main Guidance Layer
    
    private var ambientGuidanceLayer: some View {
        VStack(spacing: 0) {
            // Top spacing
            Spacer()
                .frame(height: 80)
            
            // Directional guidance zone - only show distance when not in range
            if !faceManager.ratioIsInRange {
                directionalGuidanceZone
                    .frame(maxHeight: .infinity)
            } else {
                Spacer()
            }
            
            // Bottom checklist
            bottomChecklist
                .padding(.horizontal, 16)
                .padding(.bottom, 44)
        }
    }
    
    // MARK: - Directional Guidance Zone
    
    private var directionalGuidanceZone: some View {
        let guidance = positionGuidance
        
        return ZStack {
            // Distance indicator (center overlay) - only when not in range
            if guidance.distance != .perfect {
                distanceIndicator(guidance: guidance)
            }
        }
    }
    
    // MARK: - Distance Indicator
    
    private func distanceIndicator(guidance: PositionGuidance) -> some View {
        HStack{
            Spacer()
            VStack(spacing: 12) {
                // Distance label
                Text(guidance.distance == .closer ? "Move Closer" : "Move Back")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.orange.opacity(0.3),
                                                Color.orange.opacity(0.15)
                                            ],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(
                                        Color.orange.opacity(0.4),
                                        lineWidth: 1
                                    )
                            )
                    )
                    .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
            }
            Spacer()
        }
    }
    
    // MARK: - Bottom Checklist
    
    private var bottomChecklist: some View {
        VStack(spacing: 6) {
            Text("Place face in oval and adjust as per directions provided")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.center)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.25),
                                    Color.white.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }
    
    // MARK: - Success Celebration
    
    private var successCelebration: some View {
        VStack {
            Spacer()
            
            // Success message
            VStack(spacing: 8) {
                Text("Perfect Position!")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text("Hold steady while capturing")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.green.opacity(0.2),
                                        Color.green.opacity(0.05)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.green.opacity(0.5),
                                        Color.green.opacity(0.2)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )
            )
            .shadow(color: .green.opacity(0.25), radius: 20, y: 8)
            
            Spacer()
                .frame(height: 200)
        }
    }
}

// MARK: - Supporting Types

struct PositionGuidance {
    var horizontal: Direction = .center
    var vertical: Direction = .center
    var distance: Distance = .perfect
    var horizontalIntensity: CGFloat = 0
    var verticalIntensity: CGFloat = 0
    var distanceIntensity: CGFloat = 0
}

enum Direction {
    case left, right, up, down, center
    
    var label: String {
        switch self {
        case .left: return "Move Left"
        case .right: return "Move Right"
        case .up: return "Move Up"
        case .down: return "Move Down"
        case .center: return ""
        }
    }
    
    var arrowIcon: String {
        switch self {
        case .left: return "arrow.left"
        case .right: return "arrow.right"
        case .up: return "arrow.up"
        case .down: return "arrow.down"
        case .center: return ""
        }
    }
    
    func animationOffset(_ offset: CGFloat) -> CGSize {
        switch self {
        case .left: return CGSize(width: -offset, height: 0)
        case .right: return CGSize(width: offset, height: 0)
        case .up: return CGSize(width: 0, height: -offset)
        case .down: return CGSize(width: 0, height: offset)
        case .center: return .zero
        }
    }
}

enum Distance {
    case closer, farther, perfect
}

// MARK: - Animation Modifiers

struct DirectionalPulseModifier: ViewModifier {
    let intensity: CGFloat
    let direction: Direction
    @State private var animationPhase: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(1.0 + (intensity * 0.08 * sin(animationPhase)))
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 0.8 + Double(1.0 - intensity) * 0.4)
                    .repeatForever(autoreverses: false)
                ) {
                    animationPhase = .pi * 2
                }
            }
    }
}

struct VerticalBounceModifier: ViewModifier {
    let intensity: CGFloat
    let direction: Distance
    @State private var offset: CGFloat = 0
    
    func body(content: Content) -> some View {
        let bounceDistance: CGFloat = 4 + (intensity * 4)
        
        content
            .offset(y: direction == .closer ? -offset : offset)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 0.7)
                    .repeatForever(autoreverses: true)
                ) {
                    offset = bounceDistance
                }
            }
    }
}
