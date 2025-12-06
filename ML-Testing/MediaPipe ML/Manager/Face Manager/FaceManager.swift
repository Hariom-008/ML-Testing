internal import AVFoundation
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
    @Published var dMeanPx : Float = 0
    @Published var ratioIsInRange: Bool = false
    @Published var faceLivenessScore:Float = 0
    
    
    @Published var TargetFaceOvalCoordinates:[(x: CGFloat, y: CGFloat)] = []
    @Published var TransalatedScaledFaceOvalCoordinates :[(x:CGFloat,y:CGFloat)] = []
    @Published var FaceOvalIsInTarget:Bool = false
    
    @Published var currentDistanceRatio: CGFloat = 0.0
    @Published var isNoseTipCentered:Bool = false
    
    let errorWindowPx: CGFloat = 55.0
    
    
    // MARK: - Internal Calculation Buffers
    var rawMediaPipePoints: [(x: Float, y: Float)] = []
    var CameraFeedCoordinates: [(x: Float, y: Float)] = []
    var CalculationCoordinates: [(x: Float, y: Float)] = []
    var ScreenCoordinates:[(x: CGFloat, y: CGFloat)] = []
    
    var centroid: (x: Float, y: Float)?
    
    var Translated: [(x: Float, y: Float)] = []
    var TranslatedSquareDistance: [Float] = []
    var scale: Float = 0
    
    var actualLeftList: [(x: Float, y: Float)] = []
    var actualRightList: [(x: Float, y: Float)] = []
    
    var landmarkDistanceLists: [[Float]] = []
    @Published var AllFramesOptionalAndMandatoryDistance: [[Float]] = []
    
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
    
    
    let keypoint_pair_sets = [
           //     # Set 1
                [(63, 105), (105, 66), (66, 107), (107, 9)],
        //        # Set 2
                [(293, 334), (334, 296), (296, 336), (336, 9)],
         //       # Set 3
                [(9, 8), (8, 168), (168, 6), (6, 197), (197, 195), (195, 5), (5, 4)],
          //      # Set 4
                [(2, 4)],
         //       # Set 5
                [(64, 98), (98, 97), (97, 2), (2, 326), (326, 327), (327, 294)],
        //        # Set 6
                [ (130, 226)],
        //        # Set 7
                [(263, 359)],
        //        # Set 8
                [(6, 196), (196, 236), (236, 131), (131, 49), (49, 64)],
         //       # Set 9
                [(6, 419), (419, 456), (456, 360), (360, 279), (279, 278)],
                
                [(244, 193), (193, 8)],
                [(464, 417), (417, 8)],
                [(46, 53), (53, 52), (52, 65), (65, 55)],
                [(285, 295), (295, 282), (282, 283), (283, 276)],
                [(48, 115), (115, 220), (220, 45), (45, 4), (4, 275), (275, 440), (440, 344), (344, 278)]
            ]
            
           // # Define sets for curvature calculation (triples of consecutive pairs)
            let curvature_sets = [
              //  # Set 1 curvature: [(63, 105), (105, 66), (66, 107), (107, 9)]
                [(63, 105, 66), (105, 66, 107), (66, 107, 9)],
             //   # Set 2 curvature: [(293, 334), (334, 296), (296, 336), (336, 9)]
                [(293, 334, 296), (334, 296, 336), (296, 336, 9)],
            //    # Set 5 curvature: [(98, 97), (97, 2), (2, 326), (326, 327)]
                [(64, 98, 97), (98, 97, 2), (97, 2, 326), (2, 326, 327),(326, 327, 294)],
            //    # Set 6 curvature: [(226, 247), (247, 30), (30, 29), (29, 27), (27, 28), (28, 56), (56, 190)]
                [(226, 247, 30), (247, 30, 29), (30, 29, 27), (29, 27, 28), (27, 28, 56), (28, 56, 190)],
            //    # Set 7 curvature: [(446, 467), (467, 260), (260, 259), (259, 257), (257, 258), (258, 286), (286, 414)]
                [(446, 467, 260), (467, 260, 259), (260, 259, 257), (259, 257, 258), (257, 258, 286), (258, 286, 414)],
                [(25, 110 , 24), (110, 24, 23), (24, 23, 22), (23, 22, 26), (22, 26, 112), (26, 112, 243)],
                [(255, 339, 254),(339,254,253), (254, 253, 252), (253, 252, 256), (252, 256, 341), (256, 341, 463)],
                [(46,53, 52), (53, 52, 65), (52, 65, 55)],
                [(285, 295, 282), (295, 282, 283), (282, 283, 276)]
            ]
    
          //  # Define sets for angle calculation (triples of consecutive pairs)
            let angle_sets = [
             //   # Set 6 angle: [(33, 130), (130, 226), (226, 247)]
                [(33, 130, 226), (130, 226, 247)],
             //   # Set 7 angle: [(263, 359), (359, 446), (446, 467)]
                [(263, 359, 446), (359, 446, 467)],
                [(130, 226, 25)],
                [(263, 359, 255)]
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
