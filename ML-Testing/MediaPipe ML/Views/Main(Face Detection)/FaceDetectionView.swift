import SwiftUI
import AVFoundation
import MediaPipeTasksVision
import Combine

struct FaceDetectionView: View {
    
    // ✅ CORRECT: Both created as StateObjects
    @StateObject private var faceManager: FaceManager
    @StateObject private var cameraSpecManager: CameraSpecManager
    
    // ✅ CORRECT: Created without FaceManager dependency
    @StateObject private var ncnnViewModel = NcnnLivenessViewModel()

    let onComplete: () -> Void

    // EAR series
    @State private var earSeries: [CGFloat] = []
    private let earMaxSamples = 180
    private let earRange: ClosedRange<CGFloat> = 0.0...0.5
    private let blinkThreshold: CGFloat = 0.21

    // Pose buffers
    @State private var pitchSeries: [CGFloat] = []
    @State private var yawSeries:   [CGFloat] = []
    @State private var rollSeries:  [CGFloat] = []
    private let poseMaxSamples = 180
    private let poseRange: ClosedRange<CGFloat> = (-.pi)...(.pi)

    // Animation state for frame recording indicator
    @State private var showRecordingFlash: Bool = false
    @State private var hideOverlays: Bool = false
    
    init(onComplete: @escaping () -> Void) {
        // Create shared instances
        let camSpecManager = CameraSpecManager()
        _cameraSpecManager = StateObject(wrappedValue: camSpecManager)
        _faceManager = StateObject(wrappedValue: FaceManager(cameraSpecManager: camSpecManager))
        // ✅ No need to pass FaceManager here anymore!
        
        self.onComplete = onComplete
    }

    var body: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let screenHeight = geometry.size.height
            let isCompact = screenWidth < 1024 || screenHeight < 768
            
            ZStack {
                // Camera preview
                MediapipeCameraPreviewView(faceManager: faceManager)
                    .ignoresSafeArea()
                
                FixedTargetOvalOverlay(
                    imageSize: faceManager.imageSize,
                    screenSize: geometry.size,
                    irisDistanceRatio: faceManager.irisDistanceRatio,
                    faceManager: faceManager
                )
                
                // 👁️ Gaze vector overlay (visible after Stop)
                if faceManager.isMovementTracking {
                    GazeVectorCard(
                        gazeVector: faceManager.GazeVector,
                        screenSize: geometry.size
                    )
                    .transition(.opacity.combined(with: .scale))
                    .animation(.easeInOut(duration: 0.3), value: faceManager.isMovementTracking)
                }

                // 📊 Top-right: frames indicator + brightness + liveness
                VStack {
                    HStack {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(faceManager.isFaceReal ? Color.green : Color.red.opacity(0.7))
                                .frame(width: 12, height: 12)
                                .scaleEffect(showRecordingFlash ? 1.2 : 1.0)
                                .animation(.easeInOut(duration: 0.2), value: showRecordingFlash)
                            
                            Text(faceManager.isFaceReal ? "Real Face" : "Spoof")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                            
                            Text("(\(String(format: "%.2f", faceManager.faceLivenessScore)))")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.black.opacity(0.6))
                        )
                        .padding(.trailing, 16)
                        .padding(.top, 60)
                        
                        Spacer()
                        
                        if faceManager.totalFramesCollected > 0 {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(showRecordingFlash ? Color.green : Color.green.opacity(0.3))
                                    .frame(width: 12, height: 12)
                                    .scaleEffect(showRecordingFlash ? 1.2 : 1.0)
                                    .animation(.easeInOut(duration: 0.2), value: showRecordingFlash)
                                
                                Text("Frames: \(faceManager.totalFramesCollected)")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(Color.black.opacity(0.6))
                            )
                            .padding(.trailing, 16)
                            .padding(.top, 60)
                        }
                    }
                    .padding(.horizontal,12)
                    
                    HStack {
                        Spacer()
                        BrightnessControlView()
                    }
                    Spacer()
                }
                
                // 🔻 Bottom overlays: controls + graphs
                VStack(spacing: 0) {
                    Spacer()
                    Spacer()
                    
                    // Head pose stability indicator
                    HStack(spacing: 8) {
                        if faceManager.isHeadPoseStable() {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 10, height: 10)
                            Text("Head Stable")
                                .font(.caption)
                                .foregroundColor(.white)
                        } else {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 10, height: 10)
                            Text("Stabilizing...")
                                .font(.caption)
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 15)
                            .fill(Color.black.opacity(0.6))
                    )
                    
                    Spacer()
            
                    // Control buttons row
                    HStack(spacing: isCompact ? 12 : 20) {
                        Spacer()
                        
                        if faceManager.isCentreTracking {
                            Button {
                                faceManager.isCentreTracking = false
                                faceManager.isMovementTracking = true
                                faceManager.calculateCenterMeans()
                            } label: {
                                Text("Stop")
                                    .font(.system(size: isCompact ? 14 : 16, weight: .semibold))
                                    .padding(.horizontal, isCompact ? 16 : 24)
                                    .padding(.vertical, isCompact ? 10 : 12)
                                    .background(Color.red)
                                    .foregroundColor(.white)
                                    .cornerRadius(isCompact ? 8 : 10)
                            }
                            .transition(.scale.combined(with: .opacity))
                        } else {
                            Button {
                                faceManager.isCentreTracking = true
                                faceManager.isMovementTracking = false
                                faceManager.actualLeftList.removeAll()
                                faceManager.actualRightList.removeAll()
                            } label: {
                                Text("Start")
                                    .font(.system(size: isCompact ? 14 : 16, weight: .semibold))
                                    .padding(.horizontal, isCompact ? 16 : 24)
                                    .padding(.vertical, isCompact ? 10 : 12)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(isCompact ? 8 : 10)
                            }
                            .transition(.scale.combined(with: .opacity))
                        }
                        
                        Button {
                            faceManager.resetForNewUser()
                        } label: {
                            Text("Reset")
                                .font(.system(size: isCompact ? 14 : 16, weight: .semibold))
                                .padding(.horizontal, isCompact ? 16 : 24)
                                .padding(.vertical, isCompact ? 10 : 12)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(isCompact ? 8 : 10)
                        }
                        
                        Button {
                            onComplete()
                        } label: {
                            HStack(spacing: 6) {
                                Text("Scan Complete")
                            }
                            .font(.system(size: isCompact ? 14 : 16, weight: .semibold))
                            .padding(.horizontal, isCompact ? 16 : 24)
                            .padding(.vertical, isCompact ? 10 : 12)
                            .foregroundColor(.white)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.green)
                            )
                        }
                        Spacer()
                    }
                    .padding(.horizontal, isCompact ? 12 : 16)
                    .animation(.easeInOut(duration: 0.2), value: faceManager.isCentreTracking)
                    
                    Spacer()
                        .frame(maxHeight: isCompact ? 16 : 24)
                    
                    // Overlays Section (graphs + normalized points)
                    if !hideOverlays {
                        if isCompact {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 20) {
                                    overlayCards(
                                        screenWidth: screenWidth,
                                        screenHeight: screenHeight,
                                        isCompact: true
                                    )
                                }
                                .padding(.leading, 20)
                            }
                            .frame(height: min(screenHeight * 0.3, 220))
                        } else {
                            HStack(spacing: 16) {
                                Spacer()
                                overlayCards(
                                    screenWidth: screenWidth,
                                    screenHeight: screenHeight,
                                    isCompact: false
                                )
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    
                    Spacer()
                        .frame(height: isCompact ? 12 : 24)
                }
            }
            // EAR feed (cheap, per-frame is OK)
            .onChange(of: faceManager.EAR) { newEAR in
                var s = earSeries
                s.append(CGFloat(newEAR))
                if s.count > earMaxSamples {
                    s.removeFirst(s.count - earMaxSamples)
                }
                earSeries = s
            }
            // Pose feed from NormalizedPoints – throttled to ~10 Hz
            .onReceive(
                faceManager.$NormalizedPoints
                    .throttle(for: .milliseconds(100), scheduler: RunLoop.main, latest: true)
            ) { pts in
                if let (pitch, yaw, roll) = faceManager.computeAngles(from: pts) {
                    var p = pitchSeries; p.append(CGFloat(pitch))
                    var y = yawSeries;   y.append(CGFloat(yaw))
                    var r = rollSeries;  r.append(CGFloat(roll))
                    
                    let cap = poseMaxSamples
                    if p.count > cap { p.removeFirst(p.count - cap) }
                    if y.count > cap { y.removeFirst(y.count - cap) }
                    if r.count > cap { r.removeFirst(r.count - cap) }
                    
                    pitchSeries = p
                    yawSeries = y
                    rollSeries = r
                }
            }
            // Trigger flash animation when new frame is recorded
            .onChange(of: faceManager.frameRecordedTrigger) { _ in
                showRecordingFlash = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    showRecordingFlash = false
                }
            }
            // Handle successful upload - go back
            .onChange(of: faceManager.uploadSuccess) { success in
                if success {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        faceManager.resetForNewUser()
                        onComplete()
                    }
                }
            }
            .alert("Upload Status", isPresented: .constant(faceManager.uploadError != nil || faceManager.uploadSuccess)) {
                Button("OK") {
                    faceManager.uploadError = nil
                }
            } message: {
                if let error = faceManager.uploadError {
                    Text("Error: \(error)")
                } else if faceManager.uploadSuccess {
                    Text("Face pattern uploaded successfully! ✅")
                }
            }
        }
        .onAppear {
            // ✅ Load models
            ncnnViewModel.loadModels()
            
            // ✅ Set up the callback to update FaceManager
            ncnnViewModel.onLivenessUpdated = { [weak faceManager] score in
                faceManager?.updateFaceLivenessScore(score)
            }
            
            debugLog("✅ FaceDetectionView appeared, callback connected")
        }
        // NCNN frames – throttled to avoid overloading CPU/GPU
        .onReceive(
            faceManager.$latestPixelBuffer
                .compactMap { $0 }
                .throttle(for: .milliseconds(150), scheduler: RunLoop.main, latest: true)
        ) { buffer in
            ncnnViewModel.processFrame(buffer)
        }
    }

    @ViewBuilder
    private func phoneNumberInputOverlay(isCompact: Bool) -> some View {
        EmptyView()
    }
    
    private func instructionRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.cyan)
                .frame(width: 24)
            
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.8))
            
            Spacer()
        }
    }
    
    @ViewBuilder
    private func overlayCards(screenWidth: CGFloat, screenHeight: CGFloat, isCompact: Bool) -> some View {
        let cardWidth = isCompact ? min(screenWidth * 0.6, 240) : min(screenWidth * 0.18, 260)
        let cardHeight = isCompact ? min(screenHeight * 0.25, 160) : min(screenHeight * 0.22, 180)
        
        PoseGraphCard(
            pitch: pitchSeries,
            yaw:   yawSeries,
            roll:  rollSeries,
            minY: poseRange.lowerBound,
            maxY: poseRange.upperBound
        )
        .frame(width: cardWidth, height: cardHeight)

        EARGraphCard(
            values: earSeries,
            minY: earRange.lowerBound,
            maxY: earRange.upperBound,
            threshold: blinkThreshold
        )
        .frame(width: cardWidth, height: cardHeight)
        .shadow(color: .black.opacity(0.3), radius: 6)

        NormalizedPointsOverlay(
            points: faceManager.NormalizedPoints,
            pointSize: isCompact ? 2.5 : 3.0,
            insetRatio: 0.12,
            smoothingAlpha: 0.25
        )
        .frame(width: cardWidth, height: cardHeight)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 6)
    }
}
