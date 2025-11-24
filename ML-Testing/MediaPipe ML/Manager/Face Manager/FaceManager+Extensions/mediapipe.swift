import Foundation
import MediaPipeTasksVision

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
                self.irisDistanceRatio = nil
                self.faceBoundingBox = nil
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
//            if let (pitch, yaw, roll) = self.computeAngles(from: self.NormalizedPoints) {
//                self.Pitch = pitch
//                self.Yaw = yaw
//                self.Roll = roll
//            } else {
//                self.Pitch = 0
//                self.Yaw = 0
//                self.Roll = 0
//            }
            
            // ✅ ALWAYS calculate pattern (conditions checked inside function)
            // Calculate Keypoint Distance, Curvature and Angles and then find Feature vector before PCD & LDA
            self.CalculateFeatureVectorBeforeMultiplication()
        }
    }
}
