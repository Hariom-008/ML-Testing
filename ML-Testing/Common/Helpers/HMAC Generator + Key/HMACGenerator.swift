import Foundation
import CryptoKit

struct HMACGenerator {
    static func createHMAC(user: User) -> String {
        let secret = "ByoSyncPayWithFace"
        
        // Encode User to JSON string
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        
        guard let jsonData = try? encoder.encode(user),
              let bodyString = String(data: jsonData, encoding: .utf8) else {
            print("Failed to encode user to JSON")
            return "" // Return empty string on failure
        }
        
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let dataToSign = bodyString
        
        print("Data to sign => \(dataToSign)")
        
        let key = SymmetricKey(data: Data(secret.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: Data(dataToSign.utf8), using: key)
        let signatureHex = signature.map { String(format: "%02hhx", $0) }.joined()
        
        print("Generated HMAC Signature => \(signatureHex)")
        print("Timestamp => \(timestamp)")
        
        return signatureHex // Return the signature
    }
        static func generateHMAC(jsonString: String) -> String {
            let secret = "ByoSyncPayWithFace"
            let key = SymmetricKey(data: Data(secret.utf8))
            let signature = HMAC<SHA256>.authenticationCode(for: Data(jsonString.utf8), using: key)
            let signatureHex = signature.map { String(format: "%02hhx", $0) }.joined()
            return signatureHex
        }
}
