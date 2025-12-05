//
//  FetchFaceIDRepository.swift
//  ML-Testing
//
//  Created by Hari's Mac on 05.12.2025.
//

import Foundation
import Alamofire

struct RequestFetchFaceID:Encodable{
    var deviceKeyHash:String
}

protocol FaceIDFetchRepositoryType {
    /// Fetch stored FaceID data for a given deviceKeyHash
    func fetchFaceID(
        _ request: RequestFetchFaceID,
        completion: @escaping (Result<ResponseGetFaceIDAPI, APIError>) -> Void
    )
}

final class FaceIDFetchRepository: FaceIDFetchRepositoryType {
    
    private let apiClient: APIClient
    
    // Adjust to your actual route if different
    private var fetchFaceIDURL: String = UserAPIEndpoint.FaceScan.GetFaceID
    
    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }
    
    func fetchFaceID(
        _ request: RequestFetchFaceID,
        completion: @escaping (Result<ResponseGetFaceIDAPI, APIError>) -> Void
    ) {
        // Convert Encodable → Alamofire Parameters
        let parameters: Parameters = [
            "deviceKeyHash": request.deviceKeyHash
        ]
        
        apiClient.request(
            fetchFaceIDURL,
            method: .post,
            parameters: parameters,
            headers: nil,
            completion: completion
        )
    }
}
