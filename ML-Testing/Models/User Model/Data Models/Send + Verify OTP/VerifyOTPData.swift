//
//  VerifyOTPData.swift
//  ByoSync
//
//  Created by Hari's Mac on 30.10.2025.
//

import Foundation
struct VerifyOTPData: Codable {
    let token: String?
    let refreshToken: String?
    let user: UserData?
    let isNewUser: Bool?
}
