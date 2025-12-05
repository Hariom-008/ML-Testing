//
//  BCHDemoView.swift
//  ML-Testing
//
//  Created by Hari's Mac on 02.12.2025.
//

import Foundation
import SwiftUI

struct BiometricDemoView: View {
    @State private var distancesText: String = ""  // comma/space separated 316 numbers
    @State private var registration: BiometricBCH.RegistrationData?
    @State private var verificationResult: BiometricBCH.VerificationResult?
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Input distances (316 values)")) {
                    TextEditor(text: $distancesText)
                        .frame(minHeight: 120)
                        .font(.system(.footnote, design: .monospaced))
                        .border(Color.secondary)
                    
                    Text("Format: numbers separated by spaces or commas.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section {
                    Button("Register Biometric") {
                        runRegistration()
                    }
                    .disabled(parsedDistances().count == 0)
                    
                    Button("Verify Biometric") {
                        runVerification()
                    }
                    .disabled(registration == nil || parsedDistances().count == 0)
                }
                
                if let registration {
                    Section(header: Text("Registration Data")) {
                        Text("Helper length: \(registration.helper.count) bits")
                        Text("HashHex (first 16): \(registration.hashHex.prefix(16))…")
                        Text("Timestamp: \(registration.timestamp.description)")
                            .font(.caption)
                    }
                }
                
                if let result = verificationResult {
                    Section(header: Text("Verification Result")) {
                        Text("Success: \(result.success ? "✅" : "❌")")
                        Text(String(format: "Match: %.2f %%", result.matchPercentage))
                        Text(String(format: "Error: %.2f %%", result.errorPercentage))
                        Text("Num Errors: \(result.numErrors)")
                        Text(String(format: "HashBits similarity: %.2f %%", result.hashBitsSimilarity))
                        Text("Hash match: \(result.hashMatch ? "Yes" : "No")")
                        Text("Threshold: \(String(format: "%.1f", result.threshold)) %")
                        if let reason = result.reason {
                            Text("Reason: \(reason)")
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                    }
                }
                
                if let errorMessage {
                    Section(header: Text("Error")) {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Biometric BCH Demo")
        }
    }
    
    // MARK: - Helpers
    
    private func parsedDistances() -> [Double] {
        distancesText
            .replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .compactMap { Double($0) }
    }
    
    private func runRegistration() {
        errorMessage = nil
        verificationResult = nil
        
        let dists = parsedDistances()
        do {
            let reg: BiometricBCH.RegistrationData
            if dists.count == BiometricBCH.numDistances {
                reg = try BiometricBCH.registerBiometric(distances: dists)
            } else {
                throw BiometricError.invalidDistanceCount(
                    expected: BiometricBCH.numDistances,
                    actual: dists.count
                )
            }
            registration = reg
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func runVerification() {
        errorMessage = nil
        
        guard let registration = registration else {
            errorMessage = "No registration data available."
            return
        }
        
        let dists = parsedDistances()
        do {
            let result = try BiometricBCH.verifyBiometric(
                distances: dists,
                registrationData: [registration],
                index: 0
            )
            verificationResult = result
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
