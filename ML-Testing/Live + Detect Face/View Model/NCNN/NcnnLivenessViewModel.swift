import Foundation
import Combine
import SwiftUI
import AVFoundation
import MediaPipeTasksVision

class NcnnLivenessViewModel: ObservableObject {
    @Published var detectedFaces: [FaceBox] = []
    @Published var livenessScore: Float?
    @Published var isProcessingModels = false
    @Published var errorMessage: String?
    
    private var faceDetector: FaceDetector?
    private var liveness: Live?
    
    private let processingQueue = DispatchQueue(label: "NcnnProcessingQueue")
    private var isProcessingFrame = false
    private var modelsLoaded = false
    
    // ✅ NEW: Use closure callback instead of injecting FaceManager
    var onLivenessUpdated: ((Float) -> Void)?
    
    init() {
        debugLog("🔵 Initializing NCNN view model.")
        faceDetector = FaceDetector()
        liveness = Live()
    }
    
    func loadModels() {
        guard !modelsLoaded && !isProcessingModels else {
            debugLog("⚠️ Models already loaded or loading")
            return
        }
        
        isProcessingModels = true
        errorMessage = nil
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let faceResult = self.faceDetector?.loadModel() ?? -1
            if faceResult != 0 {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to load face detection model"
                    self.isProcessingModels = false
                }
                return
            }
            
            let liveResult = self.liveness?.loadModel() ?? -1
            if liveResult != 0 {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to load liveness model"
                    self.isProcessingModels = false
                }
                return
            }
            
            DispatchQueue.main.async {
                self.modelsLoaded = true
                self.isProcessingModels = false
                debugLog("✅ NCNN models loaded successfully")
            }
        }
    }
    
    func processFrame(_ pixelBuffer: CVPixelBuffer) {
        guard modelsLoaded else { return }
        guard !isProcessingFrame else { return }
        
        isProcessingFrame = true
        let buffer = pixelBuffer   // capture for async
        
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            
            let width = CVPixelBufferGetWidth(buffer)
            let height = CVPixelBufferGetHeight(buffer)
            
            guard let rgbaData = Self.makeRGBAData(from: buffer) else {
                debugLog("❌ Failed to convert pixel buffer to RGBA")
                DispatchQueue.main.async {
                    self.isProcessingFrame = false
                }
                return
            }
            
            let orientation = 0
            
            do {
                let faces = try self.faceDetector?.detect(
                    yuv: rgbaData,
                    width: width,
                    height: height,
                    orientation: orientation
                ) ?? []
                
                var liveScore: Float? = nil
                if let firstFace = faces.first {
                    liveScore = try? self.liveness?.detect(
                        yuv: rgbaData,
                        width: width,
                        height: height,
                        orientation: orientation,
                        faceBox: firstFace
                    )
                }
                
                DispatchQueue.main.async {
                    self.detectedFaces = faces
                    if let score = liveScore {
                        self.livenessScore = score
                        // ✅ Call the closure callback
                        self.onLivenessUpdated?(score)
                        debugLog("🎭 Liveness score: \(score)")
                    }
                    self.isProcessingFrame = false
                }
            } catch {
                debugLog("❌ NCNN processing error: \(error)")
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.isProcessingFrame = false
                }
            }
        }
    }
    
    // Convert 32BGRA from camera → RGBA
    private static func makeRGBAData(from imageBuffer: CVImageBuffer) -> Data? {
        CVPixelBufferLockBaseAddress(imageBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(imageBuffer) else {
            return nil
        }
        
        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer)
        
        let srcPtr = baseAddress.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)
        
        var rgba = Data(count: width * height * 4)
        rgba.withUnsafeMutableBytes { destRaw in
            guard let dstBase = destRaw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return
            }
            
            for y in 0..<height {
                let srcRow = srcPtr.advanced(by: y * bytesPerRow)
                let dstRow = dstBase.advanced(by: y * width * 4)
                
                for x in 0..<width {
                    let srcPixel = srcRow.advanced(by: x * 4) // BGRA
                    let dstPixel = dstRow.advanced(by: x * 4) // RGBA
                    
                    let b = srcPixel[0]
                    let g = srcPixel[1]
                    let r = srcPixel[2]
                    let a = srcPixel[3]
                    
                    dstPixel[0] = r
                    dstPixel[1] = g
                    dstPixel[2] = b
                    dstPixel[3] = a
                }
            }
        }
        
        return rgba
    }
}

#if DEBUG
func debugLog(_ message: @autoclosure () -> String) {
    print(message())
}
#else
func debugLog(_ message: @autoclosure () -> String) { }
#endif
