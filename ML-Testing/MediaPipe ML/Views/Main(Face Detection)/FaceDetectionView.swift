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
    
    // UI State for enrollment/verification
    @State private var isEnrolled: Bool = false
    @State private var showAlert: Bool = false
    @State private var alertTitle: String = ""
    @State private var alertMessage: String = ""
    @State private var isProcessing: Bool = false
    
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
                
                // Processing overlay
                if isProcessing {
                    ZStack {
                        Color.black.opacity(0.5)
                            .ignoresSafeArea()
                        
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.5)
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            
                            Text("Processing...")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                        .padding(32)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.black.opacity(0.8))
                        )
                    }
                }
                
                VStack {
                    // Top status bar
                    HStack(spacing: 16) {
                        // Enrollment status
                        HStack(spacing: 8) {
                            Image(systemName: isEnrolled ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(isEnrolled ? .green : .red)
                            Text(isEnrolled ? "Enrolled" : "Not Enrolled")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.black.opacity(0.7))
                        )
                        .foregroundColor(.white)
                        
                        Spacer()
                        
                        // Frame counter
                        HStack(spacing: 8) {
                            Image(systemName: "camera.fill")
                            Text("\(faceManager.totalFramesCollected)")
                                .font(.system(size: 14, weight: .bold))
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(faceManager.totalFramesCollected >= 80 ? Color.green.opacity(0.8) : Color.black.opacity(0.7))
                        )
                        .foregroundColor(.white)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 60)
                    
                    Spacer()
                    
                    // Bottom buttons
                    VStack(spacing: 12) {
                        // MARK: - Register button
                        Button {
                            handleRegister()
                        } label: {
                            HStack {
                                Image(systemName: "person.badge.plus.fill")
                                Text("Register")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(registerButtonColor())
                            )
                            .foregroundColor(.white)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                            )
                        }
                        .disabled(!canRegister())
                        .opacity(canRegister() ? 1.0 : 0.5)
                        
                        // MARK: - Login button
                        Button {
                            handleLogin()
                        } label: {
                            HStack {
                                Image(systemName: "lock.shield.fill")
                                Text("Login")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(loginButtonColor())
                            )
                            .foregroundColor(.white)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                            )
                        }
                        .disabled(!canLogin())
                        .opacity(canLogin() ? 1.0 : 0.5)
                        
                        // MARK: - Clear enrollment button (for testing)
                        Button {
                            handleClearEnrollment()
                        } label: {
                            HStack {
                                Image(systemName: "trash.fill")
                                Text("Clear Enrollment")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.red.opacity(0.7))
                            )
                            .foregroundColor(.white)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                            )
                        }
                        .disabled(!isEnrolled)
                        .opacity(isEnrolled ? 1.0 : 0.5)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
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
            .alert(alertTitle, isPresented: $showAlert) {
                Button("OK") {
                    showAlert = false
                }
            } message: {
                Text(alertMessage)
            }
        }
        .onAppear {
            // ✅ Load models
            ncnnViewModel.loadModels()
            
            // ✅ Set up the callback to update FaceManager
            ncnnViewModel.onLivenessUpdated = { [weak faceManager] score in
                faceManager?.updateFaceLivenessScore(score)
            }
            
            // Check enrollment status
            checkEnrollmentStatus()
            
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
    
    // MARK: - Helper Functions
    
    private func checkEnrollmentStatus() {
        isEnrolled = LocalEnrollmentCache.shared.loadAll() != nil
        print("📊 Enrollment status: \(isEnrolled ? "✅ Enrolled" : "❌ Not Enrolled")")
    }
    
    private func canRegister() -> Bool {
        return faceManager.totalFramesCollected >= 80 && !isProcessing
    }
    
    private func canLogin() -> Bool {
        return faceManager.totalFramesCollected >= 80 && isEnrolled && !isProcessing
    }
    
    private func registerButtonColor() -> Color {
        if isProcessing { return .gray }
        if isEnrolled { return .orange }  // Already enrolled, can re-register
        return faceManager.totalFramesCollected >= 80 ? .green : .gray
    }
    
    private func loginButtonColor() -> Color {
        if isProcessing { return .gray }
        return (faceManager.totalFramesCollected >= 80 && isEnrolled) ? .blue : .gray
    }
    
    // MARK: - Register Handler
    private func handleRegister() {
        print("\n" + String(repeating: "=", count: 50))
        print("📸 REGISTER BUTTON PRESSED")
        print("Total frames collected: \(faceManager.totalFramesCollected)")
        print(String(repeating: "=", count: 50))
        
        isProcessing = true
        
        // Validate frames
        let allFrames = faceManager.save316LengthDistanceArray()
        let validFrames = allFrames.filter { $0.count == 316 }
        let invalidCount = allFrames.count - validFrames.count
        
        print("📊 Frame Analysis:")
        print("   Total frames: \(allFrames.count)")
        print("   Valid frames (316 distances): \(validFrames.count)")
        print("   Invalid frames: \(invalidCount)")
        
        // Check if we have enough valid frames
        guard validFrames.count >= 80 else {
            print("❌ INSUFFICIENT VALID FRAMES")
            isProcessing = false
            
            alertTitle = "❌ Registration Failed"
            alertMessage = "Need at least 80 valid frames.\n\nFound: \(validFrames.count) valid\nInvalid: \(invalidCount)"
            showAlert = true
            return
        }
        
        // Proceed with enrollment
        faceManager.generateAndUploadFaceID { result in
            DispatchQueue.main.async {
                isProcessing = false
                
                switch result {
                case .success:
                    print("✅ ========================================")
                    print("✅ REGISTRATION SUCCESSFUL!")
                    print("✅ 80 enrollment records saved")
                    print("✅ ========================================")
                    
                    // Update enrollment status
                    checkEnrollmentStatus()
                    
                    // Clear frames
                    faceManager.AllFramesOptionalAndMandatoryDistance = []
                    faceManager.totalFramesCollected = 0
                    
                    // Show success alert
                    alertTitle = "✅ Registration Successful"
                    alertMessage = "Your face has been enrolled!\n\nYou can now use Login to verify your identity."
                    showAlert = true
                    
                case .failure(let error):
                    print("❌ ========================================")
                    print("❌ REGISTRATION FAILED")
                    print("❌ Error: \(error.localizedDescription)")
                    print("❌ ========================================")
                    
                    // Show error alert
                    alertTitle = "❌ Registration Failed"
                    alertMessage = "Error: \(error.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }
    
    // MARK: - Login Handler
    private func handleLogin() {
        print("\n" + String(repeating: "=", count: 50))
        print("🔐 LOGIN BUTTON PRESSED")
        print("Total frames collected: \(faceManager.totalFramesCollected)")
        print(String(repeating: "=", count: 50))
        
        isProcessing = true
        
        // Double-check enrollment exists
        guard let enrollment = LocalEnrollmentCache.shared.loadAll() else {
            print("❌ NO ENROLLMENT FOUND!")
            isProcessing = false
            checkEnrollmentStatus()
            
            alertTitle = "❌ No Enrollment Found"
            alertMessage = "Please press REGISTER first to enroll your face."
            showAlert = true
            return
        }
        
        print("✅ Found enrollment with \(enrollment.count) records")
        
        // Validate frames
        let allFrames = faceManager.save316LengthDistanceArray()
        let validFrames = allFrames.filter { $0.count == 316 }
        let invalidCount = allFrames.count - validFrames.count
        
        print("📊 Frame Analysis:")
        print("   Total frames: \(allFrames.count)")
        print("   Valid frames (316 distances): \(validFrames.count)")
        print("   Invalid frames: \(invalidCount)")
        
        // Check if we have enough valid frames
        guard validFrames.count >= 60 else {
            print("❌ INSUFFICIENT VALID FRAMES")
            isProcessing = false
            
            alertTitle = "❌ Login Failed"
            alertMessage = "Need at least 60 valid frames.\n\nFound: \(validFrames.count) valid\nInvalid: \(invalidCount)"
            showAlert = true
            return
        }
        
        // Proceed with verification
        faceManager.verifyFaceIDAgainstLocal { result in
            DispatchQueue.main.async {
                isProcessing = false
                
                // Clear frames after verification
                faceManager.AllFramesOptionalAndMandatoryDistance = []
                faceManager.totalFramesCollected = 0
                
                switch result {
                case .success(let verification):
                    let matchPercent = verification.matchPercentage
                    let matchedFrames = verification.matchCount
                    
                    if verification.success {
                        print("✅ ========================================")
                        print("✅ LOGIN SUCCESSFUL! 🎉")
                        print("✅ Match: \(String(format: "%.1f", matchPercent))%")
                        print("✅ Matched Frames: \(matchedFrames)")
                        print("✅ ========================================")
                        
                        // Show success alert
                        alertTitle = "✅ Login Successful!"
                        alertMessage = "Welcome back!\n\nMatch: \(String(format: "%.1f", matchPercent))%\nMatched Frames: \(matchedFrames)"
                        showAlert = true
                        
                    } else {
                        print("❌ ========================================")
                        print("❌ LOGIN FAILED ⛔")
                        print("❌ Match: \(String(format: "%.1f", matchPercent))%")
                        print("❌ Matched Frames: \(matchedFrames)")
                        print("❌ Reason: \(verification.reason ?? "Unknown")")
                        print("❌ ========================================")
                        
                        // Show failure alert
                        alertTitle = "❌ Login Failed"
                        alertMessage = "Face verification failed.\n\nMatch: \(String(format: "%.1f", matchPercent))%\nMatched Frames: \(matchedFrames)\n\nReason: \(verification.reason ?? "Insufficient match")"
                        showAlert = true
                    }
                    
                case .failure(let error):
                    print("❌ ========================================")
                    print("❌ VERIFICATION ERROR")
                    print("❌ Error: \(error.localizedDescription)")
                    print("❌ ========================================")
                    
                    // Show error alert
                    alertTitle = "❌ Verification Error"
                    alertMessage = "Error: \(error.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }
    
    // MARK: - Clear Enrollment Handler
    private func handleClearEnrollment() {
        print("\n🧹 CLEARING ENROLLMENT DATA")
        
        LocalEnrollmentCache.shared.clear()
        faceManager.AllFramesOptionalAndMandatoryDistance = []
        faceManager.totalFramesCollected = 0
        
        checkEnrollmentStatus()
        
        print("✅ All enrollment data cleared")
        
        alertTitle = "🧹 Data Cleared"
        alertMessage = "Enrollment data has been cleared.\n\nYou can now register again."
        showAlert = true
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
