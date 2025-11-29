//
//  Nose Tip.swift
//  ML-Testing
//
//  Created by Hari's Mac on 29.11.2025.
//

import Foundation
import SwiftUI

extension FaceManager{
    func updateNoseTipCenterStatusFromCalcCoords(tolerance: Float = 0.2) {
        guard NormalizedPoints.count > 4 else {
            isNoseTipCentered = false
            return
        }
        let nose = NormalizedPoints[4]   // now assumed centered coords
        let insideX = abs(nose.x) <= tolerance
        let insideY = abs(nose.y) <= tolerance
        isNoseTipCentered = insideX && insideY
    }
}
