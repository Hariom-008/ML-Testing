//
//  CameraSpecView.swift
//  ByoSync
//

import SwiftUI
internal import AVFoundation
import Combine
import CoreMedia
import simd

// MARK: - Model

struct CameraSpecs {
    let deviceName: String
    let position: String
    
    // Per-frame specs
    let exposureDuration: Double
    let iso: Float
    let lensPosition: Float
    let zoomFactor: Float
    
    // Static specs
    let focalLength: Float        // in mm
    let fieldOfView: Float        // in degrees
    let minISO: Float
    let maxISO: Float
    
    // Frame info
    let frameWidth: Int
    let frameHeight: Int
    let videoOrientation: AVCaptureVideoOrientation
    
    // Calibration data
    let intrinsicMatrix: matrix_float3x3?
    let intrinsicMatrixReferenceDimensions: CGSize?
    let lensDistortionLookupTable: Data?
    let inverseLensDistortionLookupTable: Data?
    let lensDistortionCenter: CGPoint?
    
    // Video stabilization
    let videoStabilizationMode: AVCaptureVideoStabilizationMode
    
    // Timestamp
    let timestamp: CMTime?
}




import SwiftUI
internal import AVFoundation
import Combine
import CoreMedia
import CoreVideo
import simd

final class CameraSpecManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    @Published var currentSpecs: CameraSpecs?

    private var captureSession: AVCaptureSession?
    private var captureDevice: AVCaptureDevice?
    private var videoOutput: AVCaptureVideoDataOutput?
    private let videoQueue = DispatchQueue(label: "camera.specs.queue")

    func startCapture() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            guard granted else {
                print("❌ Camera permission not granted")
                return
            }
            DispatchQueue.main.async {
                self.setupSession()
            }
        }
    }

    private func setupSession() {
        let session = AVCaptureSession()
        self.captureSession = session
        session.beginConfiguration()

        // Prefer TrueDepth; fallback to regular front camera
        let device =
            AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front) ??
            AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)

        guard let device else {
            print("❌ No front camera found")
            session.commitConfiguration()
            return
        }

        self.captureDevice = device

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                print("❌ Cannot add camera input")
                session.commitConfiguration()
                return
            }
            session.addInput(input)

            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = false
            output.setSampleBufferDelegate(self, queue: videoQueue)

            guard session.canAddOutput(output) else {
                print("❌ Cannot add video output")
                session.commitConfiguration()
                return
            }
            session.addOutput(output)
            self.videoOutput = output

            if let conn = output.connection(with: .video) {
                conn.videoOrientation = .portrait

                if conn.isCameraIntrinsicMatrixDeliverySupported {
                    conn.isCameraIntrinsicMatrixDeliveryEnabled = true
                }

                print("🎥 Intrinsics supported:", conn.isCameraIntrinsicMatrixDeliverySupported,
                      "enabled:", conn.isCameraIntrinsicMatrixDeliveryEnabled)
            }

            session.commitConfiguration()

            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
            }

        } catch {
            print("⚠️ Camera setup failed:", error)
            session.commitConfiguration()
        }
    }
    
    func updateFrom(sampleBuffer: CMSampleBuffer,
                    connection: AVCaptureConnection,
                    device: AVCaptureDevice) {

        guard let format = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }

        let dims = CMVideoFormatDescriptionGetDimensions(format)

        // --- Intrinsic matrix from attachment ---
        var intrinsic: matrix_float3x3?
        var refDims: CGSize?

        if let camData = CMGetAttachment(
            sampleBuffer,
            key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix,
            attachmentModeOut: nil
        ) as? Data {
            let K = camData.withUnsafeBytes { $0.load(as: matrix_float3x3.self) }
            intrinsic = K
            refDims = CGSize(width: Int(dims.width), height: Int(dims.height))
        }

        let specs = CameraSpecs(
            deviceName: device.localizedName,
            position: device.position == .front ? "Front" : "Back",
            exposureDuration: device.exposureDuration.seconds,
            iso: device.iso,
            lensPosition: device.lensPosition,
            zoomFactor: Float(device.videoZoomFactor),
            focalLength: device.lensAperture,
            fieldOfView: device.activeFormat.videoFieldOfView,
            minISO: device.activeFormat.minISO,
            maxISO: device.activeFormat.maxISO,
            frameWidth: Int(dims.width),
            frameHeight: Int(dims.height),
            videoOrientation: connection.videoOrientation,
            intrinsicMatrix: intrinsic,
            intrinsicMatrixReferenceDimensions: refDims,
            lensDistortionLookupTable: nil,
            inverseLensDistortionLookupTable: nil,
            lensDistortionCenter: nil,
            videoStabilizationMode: connection.activeVideoStabilizationMode,
            timestamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        )

        DispatchQueue.main.async {
            self.currentSpecs = specs
            if let K = intrinsic {
                print("📐 Intrinsics updated, fx = \(K.columns.0.x)")
            } else {
                print("⚠️ No intrinsics in attachment yet")
            }
        }
    }


    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {

        guard let device = captureDevice else { return }
        updateFrom(sampleBuffer: sampleBuffer, connection: connection, device: device)
    }

}

import SwiftUI

struct CameraSpecView: View {
    @StateObject private var manager = CameraSpecManager()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let s = manager.currentSpecs {
                    Text("Device: \(s.deviceName)").bold()
                    Text("Position: \(s.position)")
                    Text("Frame: \(s.frameWidth)x\(s.frameHeight)")
                    Text("FOV: \(s.fieldOfView)")
                    Text("ISO: \(s.iso)")
                    Text("Exposure: \(s.exposureDuration)")
                    Text("Zoom: \(s.zoomFactor)")

                    if let K = s.intrinsicMatrix {
                        Text("Intrinsics:")
                        Text("[\(K.columns.0.x), \(K.columns.1.x), \(K.columns.2.x)]")
                        Text("[\(K.columns.0.y), \(K.columns.1.y), \(K.columns.2.y)]")
                        Text("[\(K.columns.0.z), \(K.columns.1.z), \(K.columns.2.z)]")
                    } else {
                        Text("No intrinsics yet (attachment not present)")
                            .foregroundColor(.red)
                    }
                } else {
                    Text("Waiting for camera…")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .onAppear {
            manager.startCapture()
        }
    }
}
