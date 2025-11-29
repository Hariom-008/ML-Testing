import SwiftUI

struct DirectionalGuidanceOverlay: View {
    @ObservedObject var faceManager: FaceManager
    
    @State private var pulseScale: CGFloat = 1.0
    @State private var glowOpacity: Double = 0.3
    @State private var shimmerOffset: CGFloat = -200
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Ambient guidance layer
                if !allConditionsMet {
                    ambientGuidanceLayer
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
                
                // Success celebration
                if allConditionsMet {
                    successCelebration
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.8).combined(with: .opacity),
                            removal: .scale(scale: 1.2).combined(with: .opacity)
                        ))
                }
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: allConditionsMet)
        }
        .allowsHitTesting(false)
    }
    
    // MARK: - Computed Properties
    
    private var allConditionsMet: Bool {
        faceManager.isHeadPoseStable() &&
        faceManager.isFaceReal &&
        faceManager.FaceOvalIsInTarget &&
        faceManager.ratioIsInRange
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
        
        let threshold: CGFloat = 25
        
        var guidance = PositionGuidance()
        
        // Horizontal
        if deltaX > threshold {
            guidance.horizontal = .left
            guidance.horizontalIntensity = min(abs(deltaX) / 100, 1.0)
        } else if deltaX < -threshold {
            guidance.horizontal = .right
            guidance.horizontalIntensity = min(abs(deltaX) / 100, 1.0)
        }
        
        // Vertical
        if deltaY > threshold {
            guidance.vertical = .up
            guidance.verticalIntensity = min(abs(deltaY) / 100, 1.0)
        } else if deltaY < -threshold {
            guidance.vertical = .down
            guidance.verticalIntensity = min(abs(deltaY) / 100, 1.0)
        }
        
        // Distance
        if let ratio = faceManager.irisDistanceRatio {
            if ratio < 0.95 {
                guidance.distance = .closer
                guidance.distanceIntensity = CGFloat(min((0.95 - ratio) / 0.2, 1.0))
            } else if ratio > 1.05 {
                guidance.distance = .farther
                guidance.distanceIntensity = CGFloat(min((ratio - 1.05) / 0.2, 1.0))
            }
        }
        
        return guidance
    }
    
    private var currentIssue: GuidanceIssue {
        if !faceManager.isFaceReal {
            return .lighting
        } else if !faceManager.ratioIsInRange {
            return .distance
        } else if !faceManager.FaceOvalIsInTarget {
            return .position
        } else if !faceManager.isHeadPoseStable() {
            return .stability
        }
        return .none
    }
    
    private func calculateCenter(from points: [(x: CGFloat, y: CGFloat)]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        let sumX = points.reduce(0.0) { $0 + $1.x }
        let sumY = points.reduce(0.0) { $0 + $1.y }
        return CGPoint(x: sumX / CGFloat(points.count), y: sumY / CGFloat(points.count))
    }
    
    // MARK: - Main Guidance Layer
    
    private var ambientGuidanceLayer: some View {
        VStack(spacing: 0) {
            // Top instruction card
//            topInstructionCard
//                .padding(.top, 70)
//                .padding(.horizontal, 20)
            
            Spacer()
            
            // Directional arrows layer
            directionalArrowsLayer
            
            Spacer()
            
            // Bottom checklist
            bottomChecklist
                .padding(.bottom, 100)
                .padding(.horizontal, 20)
        }
    }
    
    // MARK: - Top Instruction Card
    
    private var topInstructionCard: some View {
        VStack(spacing: 14) {
            // Animated icon
            ZStack {
                // Glow circle
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [currentIssue.color.opacity(0.3), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 40
                        )
                    )
                    .frame(width: 80, height: 80)
                    .scaleEffect(pulseScale)
                    .opacity(glowOpacity)
                
                // Icon
                Image(systemName: currentIssue.icon)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [currentIssue.color, currentIssue.color.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: currentIssue.color.opacity(0.5), radius: 8)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    pulseScale = 1.3
                    glowOpacity = 0.6
                }
            }
            
            // Main instruction
            Text(currentIssue.instruction(for: positionGuidance))
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 28)
        .background(
            ZStack {
                // Blur background
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                
                // Gradient border
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                currentIssue.color.opacity(0.6),
                                currentIssue.color.opacity(0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
                
                // Shimmer effect
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.1), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .offset(x: shimmerOffset)
                    .mask(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                    )
            }
        )
        .shadow(color: .black.opacity(0.2), radius: 15, y: 5)
        .onAppear {
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                shimmerOffset = 200
            }
        }
    }
    
    // MARK: - Directional Arrows Layer
    
    private var directionalArrowsLayer: some View {
        let guidance = positionGuidance
        
        return ZStack {
            // Horizontal arrows
            HStack {
                if guidance.horizontal == .left {
                    directionalArrow(
                        direction: .left,
                        intensity: guidance.horizontalIntensity
                    )
                    .padding(.leading, 24)
                }
                
                Spacer()
                
                if guidance.horizontal == .right {
                    directionalArrow(
                        direction: .right,
                        intensity: guidance.horizontalIntensity
                    )
                    .padding(.trailing, 24)
                }
            }
            
            // Vertical arrows
            VStack {
                if guidance.vertical == .up {
                    directionalArrow(
                        direction: .up,
                        intensity: guidance.verticalIntensity
                    )
                    .padding(.top, 20)
                }
                
                Spacer()
                
                if guidance.vertical == .down {
                    directionalArrow(
                        direction: .down,
                        intensity: guidance.verticalIntensity
                    )
                    .padding(.bottom, 20)
                    .offset(y:40)
                }
            }
            
            // Distance indicators
            if guidance.distance != .perfect {
                distanceIndicator(guidance: guidance)
            }
        }
    }
    
    private func directionalArrow(direction: Direction, intensity: CGFloat) -> some View {
        VStack(spacing: 10) {
            ZStack {
                // Glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.cyan.opacity(0.4), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 35
                        )
                    )
                    .frame(width: 70, height: 70)
                
                // Arrow circle
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.cyan, .cyan.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                    .overlay(
                        Circle()
                            .strokeBorder(.white.opacity(0.3), lineWidth: 1.5)
                    )
                    .shadow(color: .cyan.opacity(0.5), radius: 12)
                
                // Arrow icon
                Image(systemName: direction.arrowIcon)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
            }
            .modifier(IntensityPulseModifier(intensity: intensity))
            
            // Label
            Text(direction.label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [.cyan.opacity(0.6), .cyan.opacity(0.3)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                )
                .shadow(color: .black.opacity(0.3), radius: 8)
        }
    }
    
    private func distanceIndicator(guidance: PositionGuidance) -> some View {
        VStack {
            Spacer()
            
            VStack(spacing: 16) {
                // Distance arrows
                VStack(spacing: 8) {
                    if guidance.distance == .closer {
                        //ForEach(0..<2) { index in
                            Image(systemName: "arrow.uturn.up")
                                .font(.system(size: 36))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.orange, .orange.opacity(0.6)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
//                                .opacity(index == 0 ? 1.0 : 0.5)
//                                .shadow(color: .orange.opacity(0.5), radius: 8)
                       // }
                    } else if guidance.distance == .farther {
                       // ForEach(0..<2) { index in
                            Image(systemName: "arrow.uturn.down")
                                .font(.system(size: 36))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.orange, .orange.opacity(0.6)],
                                        startPoint: .bottom,
                                        endPoint: .top
                                    )
                                )
                               // .opacity(index == 1 ? 1.0 : 0.5)
                               // .shadow(color: .orange.opacity(0.5), radius: 8)
                      //  }
                    }
                }
                .modifier(IntensityPulseModifier(intensity: guidance.distanceIntensity))
                
                // Distance label
                Text(guidance.distance == .closer ? "Move Closer" : "Move Back")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.orange.opacity(0.9), .orange.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                            )
                    )
                    .shadow(color: .orange.opacity(0.5), radius: 12)
            }
            
            Spacer()
                .frame(height: 80)
        }
    }
    
    // MARK: - Bottom Checklist
    
    private var bottomChecklist: some View {
        VStack(spacing: 4) {
            checklistItem(
                icon: "light.max",
                label: "Lighting Quality",
                isMet: faceManager.isFaceReal,
                metric: String(format: "%.0f%%", faceManager.faceLivenessScore * 100),
                progress: CGFloat(faceManager.faceLivenessScore)
            )
            
            checklistItem(
                icon: "arrow.up.and.down",
                label: "Distance",
                isMet: faceManager.ratioIsInRange,
                metric: faceManager.irisDistanceRatio.map { String(format: "%.2f", $0) } ?? "--",
                progress: min(max(CGFloat(faceManager.irisDistanceRatio ?? 0) / 1.05, 0), 1)
            )
            
            checklistItem(
                icon: "scope",
                label: "Position",
                isMet: faceManager.FaceOvalIsInTarget,
                metric: faceManager.FaceOvalIsInTarget ? "Aligned" : "Adjust",
                progress: faceManager.FaceOvalIsInTarget ? 1.0 : 0.5
            )
            
            checklistItem(
                icon: "figure.stand",
                label: "Stability",
                isMet: faceManager.isHeadPoseStable(),
                metric: faceManager.isHeadPoseStable() ? "Stable" : "Moving",
                progress: faceManager.isHeadPoseStable() ? 1.0 : 0.3
            )
        }
        .padding(12)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.3), .white.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(0.2), radius: 15, y: 5)
    }
    
    private func checklistItem(
        icon: String,
        label: String,
        isMet: Bool,
        metric: String,
        progress: CGFloat
    ) -> some View {
        HStack(spacing: 12) {
            // Icon with progress ring
            ZStack {
                // Background circle
                Circle()
                    .stroke(.white.opacity(0.2), lineWidth: 2.5)
                    .frame(width: 24, height: 24)
                
                // Progress circle
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        isMet ? Color.green : Color.orange,
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .frame(width: 24, height: 24)
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.5), value: progress)
                
                // Icon
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isMet ? .green : .white.opacity(0.6))
            }
            
            // Label
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(isMet ? .white : .white.opacity(0.7))
            
            Spacer()
            
            // Metric
            Text(metric)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(.white.opacity(0.1))
                )
            
            // Status indicator
            ZStack {
                Circle()
                    .fill(isMet ? Color.green.opacity(0.2) : Color.white.opacity(0.1))
                    .frame(width: 20, height: 20)
                
                Image(systemName: isMet ? "checkmark" : "circle")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(isMet ? .green : .white.opacity(0.4))
            }
        }
        .padding(.vertical, 6)
    }
    
    // MARK: - Success Celebration
    
    private var successCelebration: some View {
        HStack{
            Spacer()
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 10)
                
                VStack(spacing: 18) {
                    // Success icon with animation
                    ZStack {
                        // Multiple glow circles
                        ForEach(0..<3) { index in
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [.green.opacity(0.3), .clear],
                                        center: .center,
                                        startRadius: 0,
                                        endRadius: CGFloat(50 + index * 20)
                                    )
                                )
                                .frame(width: CGFloat(100 + index * 40), height: CGFloat(100 + index * 40))
                                .scaleEffect(pulseScale)
                                .opacity(0.6)
                        }
                        
                        // Success checkmark
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [.green, .green.opacity(0.7)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 72, height: 72)
                                .overlay(
                                    Circle()
                                        .strokeBorder(.white.opacity(0.3), lineWidth: 2)
                                )
                            
                            Image(systemName: "checkmark")
                                .font(.system(size: 36, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .shadow(color: .green.opacity(0.5), radius: 20)
                    }
                    
                    // Success message
                    VStack(spacing: 10) {
                        Text("Perfect Position!")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        Text("Hold steady while capturing")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(.ultraThinMaterial)
                        
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.green.opacity(0.3), .green.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.green.opacity(0.6), .green.opacity(0.3)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    }
                )
                .shadow(color: .green.opacity(0.4), radius: 25, y: 10)
                
                Spacer()
            }
            Spacer()
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
}

enum Distance {
    case closer, farther, perfect
}

enum GuidanceIssue {
    case lighting, distance, position, stability, none
    
    var icon: String {
        switch self {
        case .lighting: return "light.max"
        case .distance: return "arrow.up.and.down"
        case .position: return "scope"
        case .stability: return "figure.stand"
        case .none: return "checkmark.circle"
        }
    }
    
    var color: Color {
        switch self {
        case .lighting: return .yellow
        case .distance: return .orange
        case .position: return .cyan
        case .stability: return .blue
        case .none: return .green
        }
    }
    
    func instruction(for guidance: PositionGuidance) -> String {
        switch self {
        case .lighting:
            return "Ensure proper lighting on your face"
        case .distance:
            if guidance.distance == .closer {
                return "Move closer to the camera"
            } else if guidance.distance == .farther {
                return "Move back from the camera"
            }
            return "Adjust your distance"
        case .position:
            var parts: [String] = []
            if guidance.horizontal != .center {
                parts.append(guidance.horizontal.label.lowercased())
            }
            if guidance.vertical != .center {
                parts.append(guidance.vertical.label.lowercased())
            }
            if !parts.isEmpty {
                return "Move your head " + parts.joined(separator: " and ")
            }
            return "Center your face in the oval"
        case .stability:
            return "Hold your head still"
        case .none:
            return "Perfect! Hold steady..."
        }
    }
}

// MARK: - Animation Modifiers

struct IntensityPulseModifier: ViewModifier {
    let intensity: CGFloat
    @State private var isPulsing = false
    
    func body(content: Content) -> some View {
        let scaleFactor = 1.0 + (intensity * 0.15)
        
        content
            .scaleEffect(isPulsing ? scaleFactor : 1.0)
            .opacity(isPulsing ? (0.7 + intensity * 0.3) : 1.0)
            .animation(
                .easeInOut(duration: 0.6 + Double(1.0 - intensity) * 0.4)
                .repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear {
                isPulsing = true
            }
    }
}
