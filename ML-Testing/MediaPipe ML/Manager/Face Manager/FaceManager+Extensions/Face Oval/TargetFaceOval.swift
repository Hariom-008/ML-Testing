import Foundation
import CoreGraphics
import SwiftUI

extension FaceManager {

    /// Compute the **target** face oval for the current frame in screen space.
    func updateTargetFaceOvalCoordinates(screenWidth: CGFloat, screenHeight: CGFloat) {
        // Always reset for the new frame
        TargetFaceOvalCoordinates.removeAll(keepingCapacity: true)
        TransalatedScaledFaceOvalCoordinates.removeAll(keepingCapacity: true)

        // We need screen coordinates to be valid
        guard !ScreenCoordinates.isEmpty else {
            self.FaceOvalIsInTarget = false
            return
        }

        // 1️⃣ Extract only face-oval points from ScreenCoordinates
        for idx in faceOvalIndices {
            let p = ScreenCoordinates[idx]
            TargetFaceOvalCoordinates.append((x: p.x, y: p.y))
        }

        guard !TargetFaceOvalCoordinates.isEmpty else {
            self.FaceOvalIsInTarget = false
            return
        }

        // 2️⃣ Center around mean
        let mean = meanOfTargetFaceOvalCoordinates(TargetFaceOvalCoordinates: TargetFaceOvalCoordinates)

        var centred: [(x: CGFloat, y: CGFloat)] = []
        centred.reserveCapacity(TargetFaceOvalCoordinates.count)

        for c in TargetFaceOvalCoordinates {
            centred.append((x: c.x - mean.x, y: c.y - mean.y))
        }

        // 3️⃣ Scale using irisTargetPx and dMeanPx
        let safeDMean = max(CGFloat(dMeanPx), 0.0001)
        let scaleFactor = CGFloat(irisTargetPx) / safeDMean

        var scaled: [(x: CGFloat, y: CGFloat)] = []
        scaled.reserveCapacity(centred.count)

        for c in centred {
            scaled.append((x: c.x * scaleFactor, y: c.y * scaleFactor))
        }

        // 4️⃣ Translate to screen center
        let center = CGPoint(x: screenWidth / 2.0, y: screenHeight / 2.0)
        for c in scaled {
            TransalatedScaledFaceOvalCoordinates.append(
                (x: c.x + center.x, y: c.y + center.y)
            )
        }

        // 5️⃣ NEW: Evaluate if user face oval fits inside target oval
        evaluateFaceOvalAlignment()
    }

    func meanOfTargetFaceOvalCoordinates(
        TargetFaceOvalCoordinates: [(x: CGFloat, y: CGFloat)]
    ) -> (x: CGFloat, y: CGFloat) {
        guard !TargetFaceOvalCoordinates.isEmpty else { return (0, 0) }

        let sumX = TargetFaceOvalCoordinates.reduce(0) { $0 + $1.x }
        let sumY = TargetFaceOvalCoordinates.reduce(0) { $0 + $1.y }

        let count = CGFloat(TargetFaceOvalCoordinates.count)
        return (x: sumX / count, y: sumY / count)
    }

    // MARK: - 🔥 NEW: Check if face oval matches target oval

    func evaluateFaceOvalAlignment() {
        guard TargetFaceOvalCoordinates.count == TransalatedScaledFaceOvalCoordinates.count else {
            self.FaceOvalIsInTarget = false
            return
        }

        var allInside = true

        for i in 0..<TargetFaceOvalCoordinates.count {
            let p1 = TargetFaceOvalCoordinates[i]
            let p2 = TransalatedScaledFaceOvalCoordinates[i]

            let dx = p1.x - p2.x
            let dy = p1.y - p2.y
            let distance = sqrt(dx*dx + dy*dy)

            if distance > errorWindowPx {
                allInside = false
                break
            }
        }

        self.FaceOvalIsInTarget = allInside
    }
}
