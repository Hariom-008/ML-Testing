//
//  EyeDetectionView.swift
//  ML-Testing
//
//  Created by Hari's Mac on 22.11.2025.
//

import Foundation
import SwiftUI
import AVFoundation
import MediaPipeTasksVision
import Combine
import UIKit
import CoreImage

struct EyeDetectionView: View {
    
    
    //For Saving Frames of count 30
    @State private var isSavingFrames: Bool = false
    @State private var savedFrameCount: Int = 0
        private let maxSavedFrames = 30
    
    
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
                
                
                
            }
        }
    }
}
