//
//  GazeVectorOverlay.swift
//  ML-Testing
//
//  Created by Hari's Mac on 05.11.2025.
//

import Foundation
import SwiftUI

struct GazeVectorCard: View {
    var gazeVector: (x: Float, y: Float)
    var screenSize: CGSize
    
    // Configuration
    // Change this at the top of the struct
    private let scale: CGFloat = 5000  // Reduced from 25000
    
    // Dynamic card size based on screen
    private var cardSize: CGSize {
        let minDimension = min(screenSize.width, screenSize.height)
        let size = min(minDimension * 0.35, 300)
        return CGSize(width: size, height: size)
    }
    
    // Safe initial position (top-left with padding)
    private var initialPosition: CGPoint {
        CGPoint(
            x: cardSize.width / 2 + 20,
            y: cardSize.height / 2 + 20
        )
    }
    
    // Draggable state
    @State private var position: CGPoint?
    @GestureState private var dragOffset: CGSize = .zero
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            
            cardContent
                .frame(width: cardSize.width, height: cardSize.height)
                .position(constrainedPosition)
                .gesture(
                    DragGesture()
                        .updating($dragOffset) { value, state, _ in
                            state = value.translation
                        }
                        .onEnded { value in
                            let currentPos = position ?? initialPosition
                            position = CGPoint(
                                x: currentPos.x + value.translation.width,
                                y: currentPos.y + value.translation.height
                            )
                        }
                )
                .onAppear {
                    if position == nil {
                        position = initialPosition
                    }
                }
        }
    }
    
    // Constrain position within screen bounds
    private var constrainedPosition: CGPoint {
        let currentPos = position ?? initialPosition
        let offset = dragOffset
        
        let halfWidth = cardSize.width / 2
        let halfHeight = cardSize.height / 2
        
        let minX = halfWidth
        let maxX = screenSize.width - halfWidth
        let minY = halfHeight
        let maxY = screenSize.height - halfHeight
        
        let x = min(max(currentPos.x + offset.width, minX), maxX)
        let y = min(max(currentPos.y + offset.height, minY), maxY)
        
        return CGPoint(x: x, y: y)
    }
    
    private var cardContent: some View {
        ZStack {
            // Background with gradient
            RoundedRectangle(cornerRadius: scaledValue(20))
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.05, green: 0.05, blue: 0.15).opacity(0.95),
                            Color(red: 0.1, green: 0.1, blue: 0.2).opacity(0.95)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: scaledValue(20))
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.cyan.opacity(0.6),
                                    Color.blue.opacity(0.4)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                )
                .shadow(color: Color.cyan.opacity(0.3), radius: 15, x: 0, y: 5)
            
            VStack(spacing: 0) {
                // Header
                headerView
                    .padding(.horizontal, scaledValue(16))
                    .padding(.top, scaledValue(12))
                
                // Graph area
                GeometryReader { geometry in
                    graphContent(geometry: geometry)
                }
                .padding(scaledValue(16))
                
                // Footer with coordinates
                coordinatesView
                    .padding(.horizontal, scaledValue(16))
                    .padding(.bottom, scaledValue(12))
            }
        }
    }
    
    private var headerView: some View {
        HStack {
            HStack(spacing: scaledValue(6)) {
                Image(systemName: "eye.fill")
                    .foregroundColor(.cyan)
                    .font(.system(size: scaledValue(14)))
                
                Text("Gaze Vector")
                    .font(.system(size: scaledValue(15), weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            Spacer()
            
            Image(systemName: "hand.draw.fill")
                .foregroundColor(.white.opacity(0.4))
                .font(.system(size: scaledValue(12)))
        }
    }
    
    private func graphContent(geometry: GeometryProxy) -> some View {
        let center = CGPoint(x: geometry.size.width / 2,
                             y: geometry.size.height / 2)
        
        // Calculate raw gaze offset
        let rawGazeX = CGFloat(gazeVector.x) * scale
        let rawGazeY = -CGFloat(gazeVector.y) * scale  // ✅ Inverted Y-axis
        
        // ✅ Calculate maximum distance from center to edge (with padding)
        let padding: CGFloat = scaledValue(20) // Keep away from edges
        let maxX = (geometry.size.width / 2) - padding
        let maxY = (geometry.size.height / 2) - padding
        
        // ✅ Clamp the gaze vector to stay within bounds
        let gazeX: CGFloat
        let gazeY: CGFloat
        
        let distance = sqrt(rawGazeX * rawGazeX + rawGazeY * rawGazeY)
        let maxDistance = min(maxX, maxY)
        
        if distance > maxDistance {
            // Scale down to fit within bounds
            let ratio = maxDistance / distance
            gazeX = rawGazeX * ratio
            gazeY = rawGazeY * ratio
        } else {
            gazeX = rawGazeX
            gazeY = rawGazeY
        }
        
        return ZStack {
            // Grid
            gridLines(geometry: geometry)
            
            // Axes
            axes(geometry: geometry, center: center)
            
            // Gaze vector line with gradient
            gazeLine(center: center, gazeX: gazeX, gazeY: gazeY)
            
            // Gaze point
            gazePoint(center: center, gazeX: gazeX, gazeY: gazeY)
            
            // Center point
            centerPoint(center: center)
        }
    }
    private func gridLines(geometry: GeometryProxy) -> some View {
        Path { path in
            let step: CGFloat = geometry.size.width / 6
            
            // Vertical lines
            for i in 1..<6 {
                let x = CGFloat(i) * step
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: geometry.size.height))
            }
            
            // Horizontal lines
            for i in 1..<6 {
                let y = CGFloat(i) * step
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: geometry.size.width, y: y))
            }
        }
        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
    }
    
    private func axes(geometry: GeometryProxy, center: CGPoint) -> some View {
        Path { path in
            // X-axis
            path.move(to: CGPoint(x: 0, y: center.y))
            path.addLine(to: CGPoint(x: geometry.size.width, y: center.y))
            
            // Y-axis
            path.move(to: CGPoint(x: center.x, y: 0))
            path.addLine(to: CGPoint(x: center.x, y: geometry.size.height))
        }
        .stroke(Color.white.opacity(0.4), lineWidth: 1.5)
    }
    
    private func gazeLine(center: CGPoint, gazeX: CGFloat, gazeY: CGFloat) -> some View {
        Path { path in
            path.move(to: center)
            path.addLine(to: CGPoint(x: center.x + gazeX,
                                     y: center.y + gazeY))
        }
        .stroke(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.cyan.opacity(0.3),
                    Color.cyan
                ]),
                startPoint: UnitPoint(
                    x: 0.5,
                    y: 0.5
                ),
                endPoint: UnitPoint(
                    x: 0.5 + Double(gazeX) / 200.0,
                    y: 0.5 + Double(gazeY) / 200.0
                )
            ),
            style: StrokeStyle(lineWidth: scaledValue(3), lineCap: .round)
        )
        .shadow(color: Color.cyan.opacity(0.5), radius: scaledValue(4))
    }
    
    private func gazePoint(center: CGPoint, gazeX: CGFloat, gazeY: CGFloat) -> some View {
        ZStack {
            // Pulse effect
            Circle()
                .fill(Color.cyan.opacity(0.2))
                .frame(width: scaledValue(24), height: scaledValue(24))
            
            Circle()
                .fill(Color.cyan.opacity(0.4))
                .frame(width: scaledValue(16), height: scaledValue(16))
            
            // Main point
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color.white,
                            Color.cyan
                        ]),
                        center: .center,
                        startRadius: 1,
                        endRadius: scaledValue(5)
                    )
                )
                .frame(width: scaledValue(10), height: scaledValue(10))
        }
        .position(x: center.x + gazeX,
                  y: center.y + gazeY)
        .shadow(color: Color.cyan, radius: scaledValue(6))
    }
    
    private func centerPoint(center: CGPoint) -> some View {
        Circle()
            .stroke(Color.white.opacity(0.6), lineWidth: 1.5)
            .frame(width: scaledValue(8), height: scaledValue(8))
            .position(center)
    }
    
    private var coordinatesView: some View {
        HStack(spacing: scaledValue(12)) {
            coordinateLabel(title: "X", value: gazeVector.x, color: .cyan, icon: "arrow.left.and.right")
            
            Divider()
                .frame(height: scaledValue(20))
                .background(Color.white.opacity(0.2))
            
            coordinateLabel(title: "Y", value: gazeVector.y, color: .blue, icon: "arrow.up.and.down")
        }
        .padding(.horizontal, scaledValue(12))
        .padding(.vertical, scaledValue(8))
        .background(
            RoundedRectangle(cornerRadius: scaledValue(12))
                .fill(Color.black.opacity(0.4))
                .overlay(
                    RoundedRectangle(cornerRadius: scaledValue(12))
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
    
    private func coordinateLabel(title: String, value: Float, color: Color, icon: String) -> some View {
        HStack(spacing: scaledValue(6)) {
            Image(systemName: icon)
                .font(.system(size: scaledValue(10)))
                .foregroundColor(color.opacity(0.8))
            
            Text(title)
                .font(.system(size: scaledValue(11), weight: .bold, design: .rounded))
                .foregroundColor(color)
            
            Text(String(format: "%.4f", value))
                .font(.system(size: scaledValue(11), weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.9))
        }
        .padding(.horizontal, scaledValue(8))
        .padding(.vertical, scaledValue(4))
        .background(
            RoundedRectangle(cornerRadius: scaledValue(8))
                .fill(color.opacity(0.15))
        )
    }
    
    // Helper to scale values based on card size
    private func scaledValue(_ base: CGFloat) -> CGFloat {
        let scale = cardSize.width / 280 // 280 is the base size
        return base * scale
    }
}
