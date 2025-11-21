import AVFoundation
import UIKit
import MediaPipeTasksVision
import Combine
import simd
import Foundation
import SwiftUI

/// Main FaceManager class - Coordinates all face detection and tracking functionality
final class FaceManager: NSObject, ObservableObject {
    
    // MARK: - Dependencies
    let cameraSpecManager: CameraSpecManager
    
    // MARK: - Published UI Properties
    @Published var FaceOwnerPhoneNumber: String = "+91"
    @Published var imageSize: CGSize = .zero
    @Published var NormalizedPoints: [(x: Float, y: Float)] = []
    
    @Published var EAR: Float = 0
    @Published var Pitch: Float = 0
    @Published var Yaw: Float = 0
    @Published var Roll: Float = 0
    @Published var FaceScale: Float = 0
    
    @Published var isCentreTracking: Bool = false
    @Published var isMovementTracking: Bool = false
    @Published var GazeVector: (x: Float, y: Float) = (0, 0)
    @Published var actualLeftMean: (x: Float, y: Float) = (0, 0)
    @Published var actualRightMean: (x: Float, y: Float) = (0, 0)
    
    // Liveness
    @Published var isFaceReal: Bool = false
    @Published var rejectedFrames: Int = 0
    
    // Frame collection
    @Published var frameRecordedTrigger: Bool = false
    @Published var totalFramesCollected: Int = 0
    
    // Upload status
    @Published var isUploadingPattern: Bool = false
    @Published var uploadSuccess: Bool = false
    @Published var uploadError: String?
    @Published var hasEnteredPhoneNumber: Bool = false
    
    @Published var latestPixelBuffer: CVPixelBuffer?
    @Published var irisDistanceRatio: Float? = nil
    @Published var faceBoundingBox: CGRect? = nil
    
    // ✅ NEW: Iris target and ratio check
    @Published var irisTargetPx: Float = 0
    @Published var ratioIsInRange: Bool = false
    @Published var faceLivenessScore:Float = 0
    
    // MARK: - Internal Calculation Buffers
    var CameraFeedCoordinates: [(x: Float, y: Float)] = []
    var CalculationCoordinates: [(x: Float, y: Float)] = []
    var centroid: (x: Float, y: Float)?
    
    var Translated: [(x: Float, y: Float)] = []
    var TranslatedSquareDistance: [Float] = []
    var scale: Float = 0
    
    var actualLeftList: [(x: Float, y: Float)] = []
    var actualRightList: [(x: Float, y: Float)] = []
    
    var landmarkDistanceLists: [[Float]] = []
    @Published var AllFramesOptionalAndMandatoryDistance: [[Float]] = [[]]
    
    // MARK: - Camera Components
    var previewLayer: AVCaptureVideoPreviewLayer?
    var cameraDevice: AVCaptureDevice?
    let captureSession = AVCaptureSession()
    let videoOutput = AVCaptureVideoDataOutput()
    let sessionQueue = DispatchQueue(label: "camera.session.queue")
    let processingQueue = DispatchQueue(label: "camera.processing.queue")
    
    // MARK: - MediaPipe
    var faceLandmarker: FaceLandmarker?
    
    // MARK: - Landmark Indices (Constants)
    let faceOvalIndices: [Int] = [
        10, 338, 297, 332, 284, 251, 389, 356, 454, 323,
        361, 288, 397, 365, 379, 378, 400, 377, 152, 148,
        176, 149, 150, 136, 172, 58, 132, 93, 234, 127,
        162, 21, 54, 103, 67, 109
    ]
    
    let mandatory_landmark_pairs: [(Int, Int)] = [
        (46, 55), (70, 46), (107, 55), (70, 107),
        (336, 285), (285, 276), (276, 300), (300, 336),
        (33, 133), (133, 9), (9, 362), (362, 263),
        (33, 98), (133, 98), (9, 98),
        (9, 327), (362, 327), (263, 327),
        (9, 4),
        (98, 327), (4, 2)
    ]
    
    let midLineMandatoryLandmarks = [2, 4, 9]
    let leftMandatoryLandmarks = [70, 107, 46, 55, 33, 133, 98]
    let rightMandatoryLandmarks = [300, 336, 276, 285, 263, 362, 327]
    let mandatoryLandmarkPoints = [2, 4, 9, 70, 107, 46, 55, 33, 133, 98, 300, 336, 276, 285, 263, 362, 327]
    let selectedOptionalLandmarks = [423, 357, 349, 347, 340, 266, 330, 427, 280, 203]
    let optionalLandmarks = [423, 357, 349, 347, 340, 266, 330, 427, 280, 203, 128, 120, 118, 111, 36, 101, 207, 50, 187, 147, 411, 376, 336, 107, 351, 399, 429, 363, 134, 209, 174, 122, 151, 69, 299, 63, 156, 293, 383]
    
    // ✅ NEW: Angle triples from Android code
    let angleTriples: [(Int, Int, Int)] = [
        (70, 4, 300), (107, 4, 336), (46, 4, 276), (55, 4, 285),
        (33, 4, 263), (133, 4, 362), (98, 4, 327),
        
        (33, 4, 70), (300, 4, 263), (33, 4, 107), (336, 4, 263),
        (33, 4, 46), (276, 4, 263), (33, 4, 55), (285, 4, 263),
        (33, 4, 33), (263, 4, 263), (33, 4, 133), (362, 4, 263),
        (33, 4, 98), (327, 4, 263),
        
        (9, 70, 300), (9, 107, 336), (9, 46, 276), (9, 55, 285),
        (9, 33, 263), (9, 133, 362), (9, 98, 327),
        
        (300, 4, 336), (300, 4, 276), (300, 4, 285),
        (300, 4, 263), (300, 4, 362), (300, 4, 327),
        
        (336, 4, 276), (336, 4, 285), (336, 4, 263),
        (336, 4, 362), (336, 4, 327),
        
        (276, 4, 285), (276, 4, 263), (276, 4, 362), (276, 4, 327),
        
        (285, 4, 263), (285, 4, 362), (285, 4, 327),
        
        (263, 4, 362), (263, 4, 327),
        
        (362, 4, 327)
    ]
    
    // MARK: - Initialization
    init(cameraSpecManager: CameraSpecManager) {
        self.cameraSpecManager = cameraSpecManager
        super.init()
        setupMediaPipe()
        sessionQueue.async { [weak self] in
            self?.setupCamera()
        }
    }
    
    // MARK: - Liveness Update Method
    func updateFaceLivenessScore(_ score: Float) {
        // Update the score based on the liveness score
        self.faceLivenessScore = score
        
        // Check if the liveness score is above the threshold (0.9)
        if score > 0.9 {
            self.isFaceReal = true
        } else {
            self.isFaceReal = false
        }
    }
}

// MARK: - Array Extension
extension Array where Element == (x: Float, y: Float) {
    var asSIMD2: [SIMD2<Float>] { map { SIMD2<Float>($0.x, $0.y) } }
}
