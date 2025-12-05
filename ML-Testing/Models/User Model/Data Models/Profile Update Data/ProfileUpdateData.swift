//
//  ProfileUpdateData.swift
//  ByoSync
//
//  Created by Hari's Mac on 30.10.2025.
//

import Foundation

struct ProfileUpdateData: Codable {
    let user: UserData
    let device: DeviceData?
}
