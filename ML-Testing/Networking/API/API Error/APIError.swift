import Foundation
import Alamofire

enum APIError: Error,Sendable{
        case networkError(String)
        case serverError(Int, String)
        case decodingError(String)
        case unauthorized
        case forbidden
        case notFound
        case badRequest(String)
        case mismatchedHmac
        case failedToGenerateHmac
        case failedTomakeAPIRequest
        case dataDecodingError
        case custom(String)           // Custom CASE
        case unknown

    var localizedDescription: String {
        switch self {
        case .networkError(let message):
            return "Network error: \(message)"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        case .decodingError(let message):
            return "Failed to decode response: \(message)"
        case .unauthorized:
            return "Unauthorized. Please login again."
        case .forbidden:
            return "Access forbidden."
        case .notFound:
            return "Resource not found."
        case .badRequest(let message):
            return "Bad request: \(message)"
        case .mismatchedHmac:
            return "Hmac Key mismatched. Please login again."
        case .failedToGenerateHmac:
            return "Failed to generate HMac key."
        case .failedTomakeAPIRequest:
            return "API Request can't be made."
        case .dataDecodingError:
            return "Data Decoder Error."
        // Try to use this most times as it can fetch the exact error from backend.
        case .custom(let message):
            return message
        case .unknown:
            return "An unknown error occurred."
        }
    }
    
    
    
    // MAP Error using status Code ->
    static func map(from statusCode: Int?, error: AFError?, data: Data?) -> APIError {
        // PRIORITY: Always try to extract backend error message first
        if let backendMessage = extractErrorMessage(from: data), !backendMessage.isEmpty {
            return .custom(backendMessage)
        }
        
        // Fallback to status code specific errors if no message extracted
        if let statusCode = statusCode {
            switch statusCode {
            case 400:
                return .badRequest("Invalid request")
            case 401:
                return .unauthorized
            case 403:
                return .forbidden
            case 404:
                return .notFound
            case 409:
                return .custom("Conflict - resource already exists")
            case 500...599:
                return .serverError(statusCode, "Internal server error")
            default:
                // For any other status code, create a custom error
                return .custom("Request failed with status code \(statusCode)")
            }
        }
        
        // Handle AFError cases
        if let afError = error {
            if afError.isSessionTaskError || afError.isSessionInvalidatedError {
                return .networkError("No internet connection or request timed out.")
            }
            
            if afError.isResponseSerializationError {
                return .decodingError("Failed to parse server response.")
            }
            
            return .networkError(afError.localizedDescription)
        }
        
        return .unknown
    }
    
    private static func extractErrorMessage(from data: Data?) -> String? {
        guard let data = data else { return nil }
        
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let message = json["message"] as? String {
                    return message
                }
                if let error = json["error"] as? String {
                    return error
                }
                if let errors = json["errors"] as? [String], let first = errors.first {
                    return first
                }
            }
        } catch {
            return nil
        }
        
        return nil
    }
    
    
}
