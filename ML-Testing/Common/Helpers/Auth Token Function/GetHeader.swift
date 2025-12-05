//
//  GetHeader.swift
//  ByoSync
//
//  Created by Hari's Mac on 23.10.2025.
//

import Foundation
import Alamofire
import SwiftUI

// MARK: - Private Helper: Get Auth Headers
final class getHeader{
    static let shared = getHeader()
    private init() {}
    
    func getAuthHeaders() -> HTTPHeaders {
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "application/json")
        
        // Retrieve token from UserDefaults
        if let token = UserDefaults.standard.string(forKey: "token"), !token.isEmpty {
            headers.add(name: "Authorization", value: "Bearer \(token)")
            print("🔒 Retrieved auth token from UserDefaults")
        } else {
            print("⚠️ No auth token found in UserDefaults")
        }
        return headers
    }
    func saveAuthHeaders(_ header: String){
        guard !header.isEmpty else{
            return
        }
        UserDefaults.standard.set(header, forKey: "token")
        print("✅ Auth Header Token is Saved")
    }
}
