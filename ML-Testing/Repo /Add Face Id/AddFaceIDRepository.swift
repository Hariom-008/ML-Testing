//
//  AddFaceIDRepository.swift
//  ML-Testing
//
//  Created by Hari's Mac on 02.12.2025.
//

import Foundation
import SwiftUI
import Alamofire

struct ResponseGetFaceIDAPI: Decodable {
    let ecc: String
    let helper: String
    let hashHex: String
    let r: String
    let hashBits: String
    let id: String   // from "_id"

    enum CodingKeys: String, CodingKey {
        case ecc, helper, hashHex, r, hashBits
        case id = "_id"
    }
}
struct RequestFaceIdAPI:Decodable{
    let helper: String
    let hashHex: String
    //let r: String
    let hashBits: String
}


protocol FaceIDRepositoryType {
    /// Uploads face ID data. No response body is parsed, only success/failure.
    func uploadFaceID(
        _ request: RequestFaceIdAPI,
        completion: @escaping (Result<Void, APIError>) -> Void
    )
}

final class FaceIDRepository: FaceIDRepositoryType {
    
    private let apiClient: APIClient
    
    // Adjust this to your actual route, e.g. "/api/face-id/register"
    private var uploadFaceIDURL: String = UserAPIEndpoint.FaceScan.AddFaceId
    
    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }
    
    func uploadFaceID(
        _ request: RequestFaceIdAPI,
        completion: @escaping (Result<Void, APIError>) -> Void
    ) {
        // Convert model to Alamofire Parameters
        let parameters: Parameters = [
            "helper": request.helper,
            "hashHex": request.hashHex,
            "hashBits": request.hashBits
        ]
        
        apiClient.requestWithoutResponse(
            uploadFaceIDURL,
            method: .post,
            parameters: parameters,
            headers: nil,
            completion: completion
        )
    }
}
