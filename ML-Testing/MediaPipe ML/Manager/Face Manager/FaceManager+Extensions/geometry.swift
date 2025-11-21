//
//  geometry.swift
//  ML-Testing
//
//  Created by Hari's Mac on 19.11.2025.
//

import Foundation
import Foundation

// MARK: - Geometric Calculations
extension FaceManager {
    
    /// Calculates the centroid (center point) of the face using face oval landmarks
    func calculateCentroidUsingFaceOval() {
        guard !CalculationCoordinates.isEmpty else {
            centroid = nil
            return
        }
        
        var sumX: Float = 0
        var sumY: Float = 0
        var count: Int = 0
        
        for idx in faceOvalIndices {
            if idx >= 0 && idx < CalculationCoordinates.count {
                let p = CalculationCoordinates[idx]
                sumX += p.x
                sumY += p.y
                count += 1
            }
        }
        
        guard count > 0 else {
            centroid = nil
            return
        }
        centroid = (x: sumX / Float(count), y: sumY / Float(count))
    }
    
    /// Translates all landmarks to be centered around the centroid
    func calculateTranslated() {
        guard let c = centroid else {
            Translated = []
            return
        }
        
        // Subtract centroid from each point
        Translated = CalculationCoordinates.map { p in
            (x: p.x - c.x, y: p.y - c.y)
        }
    }
    
    /// Calculates squared distances for each translated point (for RMS calculation)
    func calculateTranslatedSquareDistance() {
        guard !Translated.isEmpty else {
            TranslatedSquareDistance = []
            return
        }
        
        // Calculate x² + y² for each translated point
        TranslatedSquareDistance = Translated.map { p in
            p.x * p.x + p.y * p.y
        }
    }
    
    /// Calculates Root Mean Square (RMS) of translated points to determine scale
    func calculateRMSOfTransalted() {
        let n = TranslatedSquareDistance.count
        guard n > 0 else {
            scale = 0
            return
        }
        
        // Calculate mean and then RMS
        let sum = TranslatedSquareDistance.reduce(0 as Float, +)
        let mean = sum / Float(n)
        scale = sqrt(max(0, mean))  // max guards against tiny negative from FP error
    }
    
    /// Normalizes all points by dividing by the scale factor
    func calculateNormalizedPoints() {
        let eps: Float = 1e-6
        guard !Translated.isEmpty, scale > eps else {
            NormalizedPoints = []
            return
        }
        
        // Divide each translated point by scale
        NormalizedPoints = Translated.map { p in
            (x: p.x / scale, y: p.y / scale)
        }
    }
}
