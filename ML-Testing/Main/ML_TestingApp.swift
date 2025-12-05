//
//  ML_TestingApp.swift
//  ML-Testing
//
//  Created by Hari's Mac on 03.11.2025.
//

import SwiftUI

@main
struct ML_TestingApp: App {
   // private let deviceRegisterRepo = DeviceRegisterRepo()
    var body: some Scene {
        WindowGroup {
            FaceDetectionView {
                print("🏁 Opening Face Detection View")
            }
//            .onAppear {
//                self.deviceRegisterRepo.checkisDeviceRegistered(deviceKey: "12345")
//            }
        }
    }
}
