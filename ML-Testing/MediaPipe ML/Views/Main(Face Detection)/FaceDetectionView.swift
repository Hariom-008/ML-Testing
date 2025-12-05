import SwiftUI
internal import AVFoundation
import MediaPipeTasksVision
import Combine
import UIKit
import CoreImage

struct FaceDetectionView: View {
    // For saving frames of count 30 (for JPEG debug / liveness etc.)
    @State private var isSavingFrames: Bool = false
    @State private var savedFrameCount: Int = 0
    private let maxSavedFrames = 30
    
    let deviceKey = "12345678a"
    
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
    
    private let hmacGenerator = HMACGenerator.self
    
    init(onComplete: @escaping () -> Void) {
        let camSpecManager = CameraSpecManager()
        _cameraSpecManager = StateObject(wrappedValue: camSpecManager)
        _faceManager = StateObject(wrappedValue: FaceManager(cameraSpecManager: camSpecManager))
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
                
                // Face detection overlays
                FacePointsOverlay(faceManager: faceManager)
                TargetFaceOvalOverlay(faceManager: faceManager)
                FaceOvalOverlay(faceManager: faceManager)
                
                DirectionalGuidanceOverlay(faceManager: faceManager)
                
                // Nose center overlay
                NoseCenterCircleOverlay(isCentered: faceManager.isNoseTipCentered)
                
                // Gaze vector (shown after calibration)
                if faceManager.isMovementTracking {
                    GazeVectorCard(
                        gazeVector: faceManager.GazeVector,
                        screenSize: geometry.size
                    )
                    .transition(.opacity.combined(with: .scale))
                    .animation(.easeInOut(duration: 0.3), value: faceManager.isMovementTracking)
                }
                
                VStack {
                    Spacer()
                    
                    // MARK: - Register button (LOCAL ONLY)
                    Button {
                        print("📸 Register tapped. totalFramesCollected = \(faceManager.totalFramesCollected)")
                        
                        faceManager.generateAndUploadFaceID { result in
                            switch result {
                            case .success:
                                print("✅ Local enrollment stored successfully")
                                faceManager.AllFramesOptionalAndMandatoryDistance = []
                            case .failure(let error):
                                print("❌ Local enrollment failed:", error)
                            }
                        }
                    } label: {
                        Text("Register")
                            .padding()
                            .background(faceManager.totalFramesCollected >= 80 ? Color.green : Color.gray)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    .disabled(faceManager.totalFramesCollected < 80)
                    .padding(.bottom, 8)

                    
                    // MARK: - Login button (LOCAL ONLY)
                    Button {
                        print("🔐 Login tapped. totalFramesCollected = \(faceManager.totalFramesCollected)")
                        
                        faceManager.verifyFaceIDAgainstLocal { result in
                            switch result {
                            case .success(let verification):
                                let approxMatch = max(0.0, 100.0 - verification.errorPercentage)
                                if verification.success {
                                    print("✅ LOCAL Login successful. Approx match: \(String(format: "%.2f", approxMatch))%  (error: \(String(format: "%.2f", verification.errorPercentage))%)")
                                } else {
                                    print("❌ LOCAL Login failed. Approx match: \(String(format: "%.2f", approxMatch))%  (error: \(String(format: "%.2f", verification.errorPercentage))%), reason: \(verification.reason ?? "Unknown"))")
                                }
                            case .failure(let error):
                                print("❌ LOCAL verification error:", error)
                            }
                        }
                    } label: {
                        Text("Login")
                            .padding()
                            .background(faceManager.totalFramesCollected >= 80 ? Color.blue : Color.gray)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    .disabled(faceManager.totalFramesCollected < 80)
                    .padding(.bottom, 24)

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
            .onReceive(faceManager.$NormalizedPoints) { _ in
                faceManager.updateNoseTipCenterStatusFromCalcCoords()
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
        // NCNN frames – throttled to avoid overloading CPU/GPU & Starts saving Frames in device
        .onReceive(
            faceManager.$latestPixelBuffer
                .compactMap { $0 }
                .throttle(for: .milliseconds(150), scheduler: RunLoop.main, latest: true)
        ) { buffer in
            // Existing NCNN processing
            ncnnViewModel.processFrame(buffer)
            
            // Optional: save JPEG frames while collecting
            if isSavingFrames && savedFrameCount < maxSavedFrames &&
                faceManager.isHeadPoseStable() &&
                faceManager.isFaceReal &&
                faceManager.FaceOvalIsInTarget &&
                faceManager.ratioIsInRange
            {
                let currentIndex = savedFrameCount
                savedFrameCount += 1
                
                DispatchQueue.global(qos: .userInitiated).async {
                    saveFrame(buffer, index: currentIndex)
                }
                
                if savedFrameCount == maxSavedFrames {
                    isSavingFrames = false
                    print("✅ Finished saving \(maxSavedFrames) frames.")
                }
            }
        }
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
    
    // MARK: - Save camera frame to Documents as JPEG
    private func saveFrame(_ pixelBuffer: CVPixelBuffer, index: Int) {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            print("❌ Failed to create CGImage for frame \(index)")
            return
        }
        
        let uiImage = UIImage(cgImage: cgImage)
        guard let jpegData = uiImage.jpegData(compressionQuality: 0.9) else {
            print("❌ Failed to get JPEG data for frame \(index)")
            return
        }
        
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileURL = docs.appendingPathComponent("frame_\(index).jpg")
        
        do {
            try jpegData.write(to: fileURL, options: .atomic)
            print("✅ Saved frame \(index) at: \(fileURL.path)")
        } catch {
            print("❌ Error saving frame \(index): \(error)")
        }
    }
}



//    @ViewBuilder
//    private func overlayCards(screenWidth: CGFloat, screenHeight: CGFloat, isCompact: Bool) -> some View {
//        let cardWidth = isCompact ? min(screenWidth * 0.6, 240) : min(screenWidth * 0.18, 260)
//        let cardHeight = isCompact ? min(screenHeight * 0.25, 160) : min(screenHeight * 0.22, 180)
//
//        PoseGraphCard(
//            pitch: pitchSeries,
//            yaw:   yawSeries,
//            roll:  rollSeries,
//            minY: poseRange.lowerBound,
//            maxY: poseRange.upperBound
//        )
//        .frame(width: cardWidth, height: cardHeight)
//
//        EARGraphCard(
//            values: earSeries,
//            minY: earRange.lowerBound,
//            maxY: earRange.upperBound,
//            threshold: blinkThreshold
//        )
//        .frame(width: cardWidth, height: cardHeight)
//        .shadow(color: .black.opacity(0.3), radius: 6)
//
//        NormalizedPointsOverlay(
//            points: faceManager.NormalizedPoints,
//            pointSize: isCompact ? 2.5 : 3.0,
//            insetRatio: 0.12,
//            smoothingAlpha: 0.25
//        )
//        .frame(width: cardWidth, height: cardHeight)
//        .overlay(
//            RoundedRectangle(cornerRadius: 12)
//                .stroke(.white.opacity(0.2), lineWidth: 1)
//        )
//        .shadow(color: .black.opacity(0.3), radius: 6)
//    }



