//
//  EAROverlayView.swift
//  ML-Testing
//
//  Created by Hari's Mac on 04.11.2025.
//

import Foundation
import SwiftUI
import simd

// MARK: - EAR Graph Card
struct EARGraphCard: View {
    let values: [CGFloat]
    let minY: CGFloat
    let maxY: CGFloat
    let threshold: CGFloat
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("EAR")
                    .font(.caption).bold()
                    .foregroundColor(.white.opacity(0.9))
                Spacer()
                Text(String(format: "%.3f", values.last ?? 0))
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
            }
            
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                
                ZStack {
                    // Threshold dashed line
                    Path { p in
                        let y = mapY(threshold, h: h, minY: minY, maxY: maxY)
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: w, y: y))
                    }
                    .stroke(Color.red.opacity(0.45),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    
                    // EAR line
                    Path { p in
                        guard values.count > 1 else { return }
                        for i in values.indices {
                            let x = CGFloat(i) / CGFloat(values.count - 1) * w
                            let y = mapY(values[i], h: h, minY: minY, maxY: maxY)
                            if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                            else { p.addLine(to: CGPoint(x: x, y: y)) }
                        }
                    }
                    .stroke(Color.cyan, lineWidth: 2)
                }
            }
            .frame(height: 100)
        }
        .padding(10)
        .background(.black.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.15)))
    }
    
    // Map EAR value into canvas Y (top-down)
    private func mapY(_ v: CGFloat, h: CGFloat, minY: CGFloat, maxY: CGFloat) -> CGFloat {
        let clamped = max(minY, min(maxY, v))
        let t = (clamped - minY) / max(0.0001, (maxY - minY)) // avoid /0
        return h * (1 - t)
    }
}
