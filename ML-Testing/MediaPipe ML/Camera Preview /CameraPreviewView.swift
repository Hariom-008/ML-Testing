import SwiftUI
internal import AVFoundation

struct MediapipeCameraPreviewView: UIViewRepresentable {
    let faceManager: FaceManager
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black

        // ✅ Properly initialize and attach the preview layer
        let previewLayer = AVCaptureVideoPreviewLayer(session: faceManager.captureSession)
        previewLayer.videoGravity = .resizeAspectFill   // maintains aspect, fills screen
        previewLayer.connection?.videoOrientation = .portrait
        previewLayer.frame = view.bounds

        view.layer.addSublayer(previewLayer)
        faceManager.previewLayer = previewLayer       // so CameraManager can reference it

        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // ✅ Ensure preview always fills the SwiftUI view size
        DispatchQueue.main.async {
            faceManager.previewLayer?.frame = uiView.bounds
        }
    }
}

