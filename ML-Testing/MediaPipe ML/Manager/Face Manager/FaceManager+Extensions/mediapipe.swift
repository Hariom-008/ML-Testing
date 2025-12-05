import Foundation
import MediaPipeTasksVision
internal import AVFoundation
import Foundation
import CoreGraphics

// MARK: - MediaPipe Setup & Delegate
extension FaceManager {
    
    /// Sets up MediaPipe Face Landmarker with live stream mode
    func setupMediaPipe() {
        do {
            guard let modelPath = Bundle.main.path(forResource: "face_landmarker", ofType: "task") else {
                print("❌ face_landmarker.task file not found")
                return
            }
            
            let options = FaceLandmarkerOptions()
            options.baseOptions.modelAssetPath = modelPath
            options.runningMode = .liveStream
            options.numFaces = 1
            options.faceLandmarkerLiveStreamDelegate = self
            
            faceLandmarker = try FaceLandmarker(options: options)
            print("✅ MediaPipe Face Landmarker initialized")
        } catch {
            print("❌ Error initializing Face Landmarker: \(error.localizedDescription)")
        }
    }
}

// MARK: - FaceLandmarkerLiveStreamDelegate
extension FaceManager: FaceLandmarkerLiveStreamDelegate {
    
    func faceLandmarker(_ faceLandmarker: FaceLandmarker,
                        didFinishDetection result: FaceLandmarkerResult?,
                        timestampInMilliseconds: Int,
                        error: Error?) {
        
        if let error = error {
            print("❌ Face detection error: \(error.localizedDescription)")
            return
        }
        
        guard let result = result,
              let firstFace = result.faceLandmarks.first else {
            // No face detected → clear data
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.CameraFeedCoordinates = []
                self.CalculationCoordinates = []
                self.ScreenCoordinates = []
                self.irisDistanceRatio = nil
                self.ratioIsInRange = false
            }
            return
        }
        
        // Validate frame size
        guard imageSize.width > 0, imageSize.height > 0 else {
            print("⚠️ Image size not yet set")
            return
        }
        
        let frameWidth = Float(imageSize.width)
        let frameHeight = Float(imageSize.height)
        // Store RAW MediaPipe normalized points (0–1)
        let rawPoints: [(x: Float, y: Float)] = firstFace.map { lm in
            (x: lm.x, y: lm.y)
        }
         rawMediaPipePoints = rawPoints
        
        // Transform landmarks to camera feed coordinates
        let coords: [(x: Float, y: Float)] = firstFace.map { lm in
            (x: lm.x * frameWidth, y: lm.y * frameHeight)
        }
        
        // Transform landmarks for calculations (flipped)
        let calcCoords: [(x: Float, y: Float)] = firstFace.map { lm in
            let flippedY = 1 - lm.y
            let flippedX = 1 - lm.x
            return (x: flippedX * frameWidth, y: flippedY * frameHeight)
        }
        
        // Process on main queue
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Store coordinates
            self.CameraFeedCoordinates = coords
            self.CalculationCoordinates = calcCoords

            // ✅ FIXED: Convert to screen coordinates with proper aspect-fill handling
            if let previewLayer = self.previewLayer {
                   let cameraResolution = CGSize(width: CGFloat(frameWidth), height: CGFloat(frameHeight))

                   let screenCoords: [(x: CGFloat, y: CGFloat)] = firstFace.map { lm in
                       let screenPoint = self.convertToScreenCoordinates(
                           normalizedX: CGFloat(lm.x),
                           normalizedY: CGFloat(lm.y),
                           previewLayer: previewLayer,
                           cameraResolution: cameraResolution
                       )
                       return (x: screenPoint.x, y: screenPoint.y)
                   }

                   self.ScreenCoordinates = screenCoords

                   // 🔥 NEW: compute target oval for this frame
                   let bounds = previewLayer.bounds
                   self.updateTargetFaceOvalCoordinates(
                       screenWidth: bounds.width,
                       screenHeight: bounds.height
                   )
               } else {
                   self.ScreenCoordinates = []
                   self.TransalatedScaledFaceOvalCoordinates.removeAll()
               }
            
            // Geometric calculations
            self.calculateCentroidUsingFaceOval()
            self.calculateTranslated()
            self.calculateTranslatedSquareDistance()
            self.calculateRMSOfTransalted()
            self.calculateNormalizedPoints()
            
            // Face metrics
            self.calculateFaceBoundingBox()
            
            // Eye Aspect Ratio
            let simdPoints = self.CalculationCoordinates.asSIMD2
            self.EAR = self.earCalc(from: simdPoints)
            
            // Gaze tracking logic
            if self.isCentreTracking && !self.isMovementTracking {
                // Calibration phase: collect samples
                self.AppendActualLeftRight()
            } else if !self.isCentreTracking && self.isMovementTracking {
                // Tracking phase: compute live gaze
                self.calculateGazeVector()
            }
            
            // Head pose estimation
            if let (pitch, yaw, roll) = self.computeAngles(from: self.NormalizedPoints) {
                self.Pitch = pitch
                self.Yaw = yaw
                self.Roll = roll
            } else {
                self.Pitch = 0
                self.Yaw = 0
                self.Roll = 0
            }
            
            // ✅ ALWAYS calculate pattern (conditions checked inside function)
            self.calculateOptionalAndMandatoryDistances()
        }
    }
}

// MARK: - Coordinate Transformation Helper
extension FaceManager {
    
    /// Converts MediaPipe normalized coordinates to screen coordinates
    /// Accounts for: portrait orientation, mirroring, and aspect fill scaling
    func convertToScreenCoordinates(
        normalizedX: CGFloat,
        normalizedY: CGFloat,
        previewLayer: AVCaptureVideoPreviewLayer,
        cameraResolution: CGSize
    ) -> CGPoint {
        
        let previewBounds = previewLayer.bounds
        let previewWidth = previewBounds.width
        let previewHeight = previewBounds.height
        
        // Calculate the actual visible area considering aspect fill
        let cameraAspectRatio = cameraResolution.width / cameraResolution.height
        let previewAspectRatio = previewWidth / previewHeight
        
        var scaleX: CGFloat = 1.0
        var scaleY: CGFloat = 1.0
        var offsetX: CGFloat = 0.0
        var offsetY: CGFloat = 0.0
        
        if cameraAspectRatio > previewAspectRatio {
            // Camera is wider - fills height, crops width
            scaleY = previewHeight / cameraResolution.height
            scaleX = scaleY
            
            let scaledCameraWidth = cameraResolution.width * scaleX
            offsetX = (previewWidth - scaledCameraWidth) / 2.0
        } else {
            // Camera is taller - fills width, crops height
            scaleX = previewWidth / cameraResolution.width
            scaleY = scaleX
            
            let scaledCameraHeight = cameraResolution.height * scaleY
            offsetY = (previewHeight - scaledCameraHeight) / 2.0
        }
        
        // Don't mirror here - the preview layer already handles mirroring
        // since conn.isVideoMirrored = true in Camera.swift
        
        // Convert normalized [0,1] to camera pixel coordinates
        let cameraX = normalizedX * cameraResolution.width
        let cameraY = normalizedY * cameraResolution.height
        
        // Scale to screen and add offset
        let screenX = cameraX * scaleX + offsetX
        let screenY = cameraY * scaleY + offsetY
        
        return CGPoint(x: screenX, y: screenY)
    }
}
