//
//  APIResponse.swift
//  ByoSync
//
//  Created by Hari's Mac on 28.10.2025.
//

import Foundation

struct APIResponse<T: Decodable>: Decodable {
    let statusCode: Int
    let data: T?
    let message: String
    let success: Bool?
    
    var isSuccess: Bool {
            return statusCode == 200
    }
}

// to add in the response where nothing in data

struct EmptyData: Codable {}
