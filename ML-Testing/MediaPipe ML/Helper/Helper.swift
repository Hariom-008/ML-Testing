//
//  Helper.swift
//  ML-Testing
//
//  Created by Hari's Mac on 04.11.2025.
//

import Foundation
import SwiftUI
final class Helper{
    static let shared = Helper()
    private init() {}
    
    
    
    // Helpers
    @inline(__always)
    func add(_ a: (x: Float, y: Float), _ b: (x: Float, y: Float)) -> (x: Float, y: Float) {
        (x: a.x + b.x, y: a.y + b.y)
    }
    
    
    @inline(__always)
    func sub(_ a: (x: Float, y: Float), _ b: (x: Float, y: Float)) -> (x: Float, y: Float) {
        (x: a.x - b.x, y: a.y - b.y)
    }
    
    @inline(__always)
    func div(_ v: (x: Float, y: Float), _ s: Float) -> (x: Float, y: Float) {
        let eps: Float = 1e-6
        let denom = abs(s) < eps ? eps : s
        return (x: v.x / denom, y: v.y / denom)
    }
    
    func calculateMean(_ coords: [(x: Float, y: Float)]) -> (x: Float, y: Float)? {
        guard !coords.isEmpty else { return nil }
        var sx: Float = 0
        var sy: Float = 0
        for p in coords {
            sx += p.x
            sy += p.y
        }
        let n = Float(coords.count)
        return (x: sx / n, y: sy / n)
    }

    
    func calculateDistance(_ p1: (x: Float, y: Float), _ p2: (x: Float, y: Float)) -> Float {
        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        return sqrt(dx * dx + dy * dy)
    }
}
