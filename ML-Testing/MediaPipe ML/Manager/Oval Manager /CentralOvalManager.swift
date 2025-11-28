//import SwiftUI
//import Combine
//
//struct OvalFrame {
//    let ovalPoints: [CGPoint]  // Already in screen coordinates
//    let scaleFactor: CGFloat
//}
//
//class CentralOvalManager: ObservableObject {
//    @Published var centralOvalPoints: [CGPoint]?
//    @Published var isFaceMatching: Bool = false
//    
//    private var buffer: [OvalFrame] = []
//    var maxBufferSize: Int = 3
//    
//    private let targetIrisWidthPx: CGFloat = 50.0
//    var errorWindowPx: CGFloat = 55.0
//    
//    private var lastCentroid: CGPoint?
//    private let movementThreshold: CGFloat = 100.0
//    
//    // ✅ Extract face oval points from full landmark array
//    private func extractFaceOvalPoints(from allPoints: [(x: CGFloat, y: CGFloat)]) -> [CGPoint] {
//        let faceOvalIndices: [Int] = [
//            10, 338, 297, 332, 284, 251, 389, 356, 454, 323,
//            361, 288, 397, 365, 379, 378, 400, 377, 152, 148,
//            176, 149, 150, 136, 172, 58, 132, 93, 234, 127,
//            162, 21, 54, 103, 67, 109
//        ]
//        
//        return faceOvalIndices.compactMap { idx in
//            guard idx < allPoints.count else { return nil }
//            let pt = allPoints[idx]
//            return CGPoint(x: pt.x, y: pt.y)
//        }
//    }
//    
//    func updateBuffer(
//        allScreenPoints: [(x: CGFloat, y: CGFloat)],
//        currentIrisWidth: CGFloat,
//        screenSize: CGSize
//    ) {
//        guard currentIrisWidth > 0 else { return }
//        
//        // Extract only face oval points
//        let faceOvalPoints = extractFaceOvalPoints(from: allScreenPoints)
//        guard !faceOvalPoints.isEmpty else { return }
//        
//        // Calculate centroid of current face
//        let sumX = faceOvalPoints.map { $0.x }.reduce(0, +)
//        let sumY = faceOvalPoints.map { $0.y }.reduce(0, +)
//        let currentCentroid = CGPoint(
//            x: sumX / CGFloat(faceOvalPoints.count),
//            y: sumY / CGFloat(faceOvalPoints.count)
//        )
//        
//        // Check for large movement - clear buffer if face moved too much
//        if let last = lastCentroid {
//            let dx = currentCentroid.x - last.x
//            let dy = currentCentroid.y - last.y
//            let movement = sqrt(dx * dx + dy * dy)
//            
//            if movement > movementThreshold {
//                print("🔄 Face moved \(Int(movement))px - clearing buffer")
//                buffer.removeAll()
//                centralOvalPoints = nil
//            }
//        }
//        
//        lastCentroid = currentCentroid
//        
//        // Calculate scale factor (to normalize face size)
//        let scale = targetIrisWidthPx / currentIrisWidth
//        
//        // Remove oldest frame if buffer is full
//        if buffer.count >= maxBufferSize {
//            buffer.removeFirst()
//        }
//        
//        // Add current frame to buffer
//        buffer.append(OvalFrame(ovalPoints: faceOvalPoints, scaleFactor: scale))
//        
//        // Once we have enough frames, calculate the central oval
//        if buffer.count == maxBufferSize {
//            let screenCenter = CGPoint(x: screenSize.width / 2, y: screenSize.height / 2)
//            centralOvalPoints = getAveragedCentralOval(screenCenter: screenCenter)
//            print("✅ Central oval created with \(centralOvalPoints?.count ?? 0) points")
//        }
//    }
//    
//    private func getAveragedCentralOval(screenCenter: CGPoint) -> [CGPoint]? {
//        guard buffer.count == maxBufferSize else { return nil }
//        
//        // Calculate average scale factor
//        let avgScale = buffer.map { $0.scaleFactor }.reduce(0, +) / CGFloat(buffer.count)
//        
//        let pointCount = buffer.first?.ovalPoints.count ?? 0
//        guard buffer.allSatisfy({ $0.ovalPoints.count == pointCount }) else { return nil }
//        
//        // Average all corresponding points across frames
//        var avgOvalPoints: [CGPoint] = []
//        
//        for i in 0..<pointCount {
//            var sumX: CGFloat = 0
//            var sumY: CGFloat = 0
//            
//            for frame in buffer {
//                sumX += frame.ovalPoints[i].x
//                sumY += frame.ovalPoints[i].y
//            }
//            
//            avgOvalPoints.append(CGPoint(
//                x: sumX / CGFloat(buffer.count),
//                y: sumY / CGFloat(buffer.count)
//            ))
//        }
//        
//        // Transform averaged points to screen center with scaling
//        return transformToCenter(ovalPoints: avgOvalPoints, scale: avgScale, screenCenter: screenCenter)
//    }
//    
//    private func transformToCenter(
//        ovalPoints: [CGPoint],
//        scale: CGFloat,
//        screenCenter: CGPoint
//    ) -> [CGPoint] {
//        // Calculate centroid of averaged oval
//        let sumX = ovalPoints.map { $0.x }.reduce(0, +)
//        let sumY = ovalPoints.map { $0.y }.reduce(0, +)
//        let centroid = CGPoint(
//            x: sumX / CGFloat(ovalPoints.count),
//            y: sumY / CGFloat(ovalPoints.count)
//        )
//        
//        // Transform: move to origin, scale, then move to screen center
//        return ovalPoints.map { point in
//            // Move to origin (remove current centroid)
//            let centered = CGPoint(x: point.x - centroid.x, y: point.y - centroid.y)
//            
//            // Apply scale
//            let scaled = CGPoint(x: centered.x * scale, y: centered.y * scale)
//            
//            // Move to screen center
//            return CGPoint(x: scaled.x + screenCenter.x, y: scaled.y + screenCenter.y)
//        }
//    }
//    
//    func checkFaceMatch(
//        allScreenPoints: [(x: CGFloat, y: CGFloat)]
//    ) {
//        guard let centralOval = centralOvalPoints else {
//            isFaceMatching = false
//            return
//        }
//        
//        // Extract current face oval points
//        let currentOvalPoints = extractFaceOvalPoints(from: allScreenPoints)
//        
//        guard currentOvalPoints.count == centralOval.count else {
//            print("❌ Size mismatch: \(currentOvalPoints.count) vs \(centralOval.count)")
//            isFaceMatching = false
//            return
//        }
//        
//        // Calculate distance between each corresponding point
//        let distances = zip(currentOvalPoints, centralOval).map { current, target in
//            let dx = current.x - target.x
//            let dy = current.y - target.y
//            return sqrt(dx * dx + dy * dy)
//        }
//        
//        // Check if ALL points are within threshold
//        let allPass = distances.allSatisfy { $0 <= errorWindowPx }
//        let maxDist = distances.max() ?? 0
//        let failCount = distances.filter { $0 > errorWindowPx }.count
//        
//        print("""
//        🎯 Match Check:
//        - All points pass: \(allPass)
//        - Max distance: \(String(format: "%.1f", maxDist))
//        - Threshold: \(errorWindowPx)
//        - Points checked: \(distances.count)
//        - Failed points: \(failCount)
//        """)
//        
//        isFaceMatching = allPass
//    }
//    
//    func getCurrentSize() -> Int {
//        return buffer.count
//    }
//    
//    func getMaxSize() -> Int {
//        return maxBufferSize
//    }
//    
//    func clear() {
//        buffer.removeAll()
//        lastCentroid = nil
//        centralOvalPoints = nil
//        isFaceMatching = false
//        print("🔄 Central oval manager cleared")
//    }
//}

//import SwiftUI
//import Combine
//
//
//class OvalManager:ObservableObject{
//  
//    @Published var faceOvalCoordinates: [CGPoint] = []
//     var ScreenCoordinates: [CGPoint]
//    
//    let faceOvalIndices: [Int] = [
//               10, 338, 297, 332, 284, 251, 389, 356, 454, 323,
//               361, 288, 397, 365, 379, 378, 400, 377, 152, 148,
//               176, 149, 150, 136, 172, 58, 132, 93, 234, 127,
//               162, 21, 54, 103, 67, 109
//           ]
//    
//    func updateFaceOvalCoordinates(_ newCoordinates: [CGPoint]) {
//        self.faceOvalCoordinates = newCoordinates
//    }
//    
//    func extractFaceOvalCoordinates(){
//        self.faceOvalCoordinates = []
//        
//    }
//}
