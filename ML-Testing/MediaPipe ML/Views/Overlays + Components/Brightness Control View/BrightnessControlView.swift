//
//  BrightnessControlView.swift
//  ByoSync-User
//
//  Created by Hari's Mac on 15.11.2025.
//

import Foundation
import SwiftUI

struct BrightnessControlView: View {
    @State private var brightness: CGFloat = UIScreen.main.brightness

    var body: some View {
        VStack(spacing: 16) {
            // Brightness Control Card
            VStack(spacing: 12) {
                // Slider with Icons
                Text("Brightness")
                    .font(.subheadline)
                HStack(spacing: 12) {
                    Image(systemName: "sun.min.fill")
                        .foregroundColor(.orange.opacity(0.6))
                        .font(.system(size: 16))
                    
                    Slider(
                        value: Binding(
                            get: { Double(brightness) },
                            set: { newValue in
                                brightness = CGFloat(newValue)
                                UIScreen.main.brightness = brightness
                            }
                        ),
                        in: 0...1
                    )
                    .tint(.orange)
                    .frame(maxWidth: 100) // Shorter slider
                }
            }
        }
    }
}

#Preview {
    BrightnessControlView()
}
