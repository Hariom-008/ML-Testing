//
//  LogRepository.swift
//  ByoSync
//

import Foundation
import Alamofire

protocol LogRepositoryProtocol {
    func sendLogs(_ logs: [BackendLogEntry], completion: @escaping (Result<LogCreateResponse, APIError>) -> Void)
}

final class LogRepository: LogRepositoryProtocol {
    
    init() {
        print("🏗️ [LOG-REPO] LogRepository initialized")
    }
    
    func sendLogs(_ logs: [BackendLogEntry], completion: @escaping (Result<LogCreateResponse, APIError>) -> Void) {
        guard !logs.isEmpty else {
            completion(.failure(.custom("No logs to send")))
            return
        }
        
        print("📤 [LOG-REPO] Sending \(logs.count) logs to backend")
        
        let headers: HTTPHeaders = [
            "Content-Type": "application/json"
        ]
        
        // Send as array of log entries
        let parameters: Parameters = [
            "logsArray": logs.map { log in
                [
                    "type": log.type,
                    "form": log.form,
                    "message": log.message,
                    "timeTaken": log.timeTaken,
                    "user": log.user
                ]
            }
        ]
        
        AF.request(
            LogEndpoint.createLogs,
            method: .post,
            parameters: parameters,
            encoding: JSONEncoding.default,
            headers: headers
        )
        .validate()
        .responseData { response in  // Changed from responseDecodable to responseData
            switch response.result {
            case .success(let data):
                Task { @MainActor in
                    do {
                        let logResponse = try JSONDecoder().decode(LogCreateResponse.self, from: data)
                        print("✅ [LOG-REPO] Logs sent successfully: \(logResponse.message)")
                        completion(.success(logResponse))
                    } catch {
                        print("❌ [LOG-REPO] Failed to decode response: \(error)")
                        completion(.failure(.custom("Failed to decode response")))
                    }
                }
                
            case .failure(let error):
                print("❌ [LOG-REPO] Failed to send logs: \(error.localizedDescription)")
                
                // Convert AFError to APIError
                let apiError: APIError
                if let statusCode = response.response?.statusCode {
                    apiError = .serverError(statusCode,"Status Code")
                } else {
                    apiError = .custom(error.localizedDescription)
                }
                
                DispatchQueue.main.async {
                    completion(.failure(apiError))
                }
            }
        }
    }
    
    deinit {
        print("♻️ [LOG-REPO] LogRepository deallocated")
    }
}
