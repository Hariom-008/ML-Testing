// AudioManager.swift
// ByoSync
//
// Created by Hari's Mac on 02.11.2025.

import Foundation
import SwiftUI
internal import AVFoundation

final class AudioManager {
    
    // Shared instance for AudioManager
    static let shared = AudioManager()
    
    private var audioPlayer: AVAudioPlayer?
    
    private init() {}
    
    // Function to play payment success sound
    func playPaymentSuccessSound() {
        playSound(named: "payment_success.mp3")
    }
    
    // General function to play any sound based on the file name
    func playSound(named fileName: String) {
        guard let url = Bundle.main.url(forResource: fileName, withExtension: nil) else {
            print("Audio file \(fileName) not found!")
            return
        }
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.play()
        } catch {
            print("Error playing sound: \(error.localizedDescription)")
        }
    }
}
