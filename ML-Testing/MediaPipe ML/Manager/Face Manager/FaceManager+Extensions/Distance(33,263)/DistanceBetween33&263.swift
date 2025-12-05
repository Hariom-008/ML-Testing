//
//  DistanceBetween33&263.swift
//  ML-Testing
//
//  Created by Hari's Mac on 29.11.2025.
//

import Foundation
import SwiftUI

extension FaceManager{
    func distanceBetween33nd263() -> Float{
        guard CalculationCoordinates.count != 0 else {
            return 0
        }
        
        let dist = Helper.shared.calculateDistance(rawMediaPipePoints[33], rawMediaPipePoints[263])
        return dist
    }
}
