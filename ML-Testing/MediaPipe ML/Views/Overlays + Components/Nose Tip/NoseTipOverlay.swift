//
//  NoseTipOverlay.swift
//  ML-Testing
//
//  Created by Hari's Mac on 29.11.2025.
//

import Foundation
import SwiftUI

struct NoseCenterCircleOverlay: View {
    let isCentered: Bool

    var body: some View {
        GeometryReader { geo in
            Circle()
                .fill(isCentered ? Color.green : Color.red)
                .frame(width: 10, height: 10)
                .position(x: geo.size.width / 2,
                          y: geo.size.height / 2)
                .animation(.easeInOut(duration: 0.15), value: isCentered)
        }
        .allowsHitTesting(false)
    }
}
