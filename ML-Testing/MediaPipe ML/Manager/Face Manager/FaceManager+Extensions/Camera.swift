//
//  CameraManager.swift
//  ML-Testing
//
//  Created by Hari's Mac on 19.11.2025.
//

import Foundation
internal import AVFoundation
import UIKit
import MediaPipeTasksVision

// MARK: - Camera Setup & Management
extension FaceManager {
    
    /// Sets up the camera capture session with appropriate configuration
    func setupCamera() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .medium   // or .vga640x480
        
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video,
                                                   position: .front) else {
            debugLog("❌ No front camera available")
            captureSession.commitConfiguration()
            return
        }
        
        self.cameraDevice = device
        
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            }
            
            videoOutput.setSampleBufferDelegate(self, queue: processingQueue)
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            if captureSession.canAddOutput(videoOutput) {
                captureSession.addOutput(videoOutput)
            }
            
            if let conn = videoOutput.connection(with: .video) {
                // Decide orientation based on device type
                let isPad = UIDevice.current.userInterfaceIdiom == .pad
                conn.videoOrientation = .portrait
                
                // Mirror front camera preview
                if conn.isVideoMirroringSupported {
                    conn.isVideoMirrored = true
                }
                
                // Enable intrinsics delivery
                if conn.isCameraIntrinsicMatrixDeliverySupported {
                    conn.isCameraIntrinsicMatrixDeliveryEnabled = true
                    debugLog("📐 Intrinsics delivery enabled on FaceManager connection")
                } else {
                    debugLog("⚠️ Intrinsics delivery NOT supported on this format")
                }
            }
            
            captureSession.commitConfiguration()
            captureSession.startRunning()
            debugLog("📸 Camera session started")
        } catch {
            debugLog("❌ Camera setup failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension FaceManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        
        // 1) Update camera specifications (intrinsics, etc.)
        if let device = cameraDevice {
            cameraSpecManager.updateFrom(
                sampleBuffer: sampleBuffer,
                connection: connection,
                device: device
            )
        }
        
        // 2) Store latest pixel buffer for UI/preview
        if let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            DispatchQueue.main.async {
                self.latestPixelBuffer = buffer
            }
        }
        
        // 3) Process frame with MediaPipe
        guard let faceLandmarker = faceLandmarker else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let image = try? MPImage(pixelBuffer: pixelBuffer) else { return }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        DispatchQueue.main.async { [weak self] in
            self?.imageSize = CGSize(width: width, height: height)
        }
        
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let timestampMs = Int(CMTimeGetSeconds(timestamp) * 1000)
        
        do {
            try faceLandmarker.detectAsync(image: image, timestampInMilliseconds: timestampMs)
        } catch {
            debugLog("❌ detectAsync failed: \(error.localizedDescription)")
        }
    }
}
