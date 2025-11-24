//
//  NoseTipOverlay.swift
//  ML-Testing
//
//  Created by Hari's Mac on 24.11.2025.
//

import Foundation
import SwiftUI

struct NoseCenterCircleOverlay: View {
    let isCentered: Bool

    var body: some View {
        GeometryReader { geo in
            Circle()
                .stroke(isCentered ? Color.green : Color.red, lineWidth: 3)
                .frame(width: 20, height: 20)
                .position(x: geo.size.width / 2,
                          y: geo.size.height / 2)
                .animation(.easeInOut(duration: 0.15), value: isCentered)
        }
        .allowsHitTesting(false)
    }
}
