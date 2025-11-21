//
//  PoseGraphCard.swift
//  ML-Testing
//
//  Created by Hari's Mac on 04.11.2025.
//

import Foundation
import SwiftUI

struct PoseGraphCard: View {
    let pitch: [CGFloat]
    let yaw:   [CGFloat]
    let roll:  [CGFloat]
    let minY: CGFloat   // e.g. -CGFloat.pi
    let maxY: CGFloat   // e.g.  CGFloat.pi
    let title: String = "Pose (rad)"

    // Get latest values
    private var currentPitch: CGFloat { pitch.last ?? 0 }
    private var currentYaw: CGFloat { yaw.last ?? 0 }
    private var currentRoll: CGFloat { roll.last ?? 0 }

    private func normalize(_ vals: [CGFloat], in rect: CGRect) -> [CGPoint] {
        guard vals.count > 1 else { return [] }
        let n = vals.count
        let dx = rect.width / CGFloat(n - 1)
        let range = maxY - minY
        return vals.enumerated().map { (i, v) in
            let x = CGFloat(i) * dx
            let clamped = min(max(v, minY), maxY)
            let t = (clamped - minY) / max(range, 1e-6) // 0..1
            let y = rect.maxY - t * rect.height
            return CGPoint(x: x, y: y)
        }
    }

    private func line(_ points: [CGPoint]) -> Path {
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: first)
        for pt in points.dropFirst() { p.addLine(to: pt) }
        return p
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with title
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            // Graph
            GeometryReader { geo in
                ZStack {
                    // grid
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.white.opacity(0.15), lineWidth: 1)

                    // midline (y=0)
                    Path { p in
                        let y0 = geo.size.height * (maxY / (maxY - minY)) // map 0 to canvas
                        p.move(to: CGPoint(x: 0, y: y0))
                        p.addLine(to: CGPoint(x: geo.size.width, y: y0))
                    }
                    .stroke(Color.white.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4,4]))

                    // series
                    line(normalize(pitch, in: geo.frame(in: .local)))
                        .stroke(Color.red, lineWidth: 2)
                    line(normalize(yaw,   in: geo.frame(in: .local)))
                        .stroke(Color.green, lineWidth: 2)
                    line(normalize(roll,  in: geo.frame(in: .local)))
                        .stroke(Color.blue, lineWidth: 2)
                }
            }
            .frame(width: 260, height: 140)
            
            // Legend with current values
            VStack(spacing: 6) {
                HStack(spacing: 12) {
                    legendItem(label: "Pitch", color: .red, value: currentPitch)
                    legendItem(label: "Yaw", color: .green, value: currentYaw)
                }
                HStack(spacing: 12) {
                    legendItem(label: "Roll", color: .blue, value: currentRoll)
                    Spacer()
                }
            }
            .font(.caption2)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(.black.opacity(0.25)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.1), lineWidth: 1))
    }
    
    // Helper view for legend items with values
    private func legendItem(label: String, color: Color, value: CGFloat) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            
            Text(label)
                .foregroundStyle(.secondary)
            
            Text(String(format: "%.3f", value))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.opacity(0.2))
                )
        }
    }
}
