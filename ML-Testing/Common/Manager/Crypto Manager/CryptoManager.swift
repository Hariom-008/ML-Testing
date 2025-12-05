import Foundation
import CryptoKit
import CommonCrypto
import Combine

protocol CryptoService: ObservableObject {
    func encrypt(text: String) -> String?
    func decrypt(encryptedData: String) -> String?
}

final class CryptoManager: CryptoService {
    // MARK: - Properties
    
    private let password: String
    private let salt: String
    private let iterations: UInt32
    private let keyLength: Int
    
    /// 🔑 Derived once and reused for all operations
    private let key: Data
    
    // Optional: shared instance for easy reuse
    static let shared = CryptoManager()
    
    // MARK: - Initialization
    
    init(
        password: String = "ByoSyncPayWithFace",
        salt: String = "ByoSync",
        iterations: UInt32 = 65536,
        keyLength: Int = 32
    ){
        self.password = password
        self.salt = salt
        self.iterations = iterations
        self.keyLength = keyLength
        
        guard let derivedKey = CryptoManager.deriveKey(
            password: password,
            salt: salt,
            iterations: iterations,
            keyLength: keyLength
        ) else {
            // For production you might want to throw instead of fatalError
            fatalError("CryptoManager: Failed to derive key")
        }
        
        self.key = derivedKey
    }
    
    // MARK: - Key derivation (called only once per instance)
    
    private static func deriveKey(
        password: String,
        salt: String,
        iterations: UInt32,
        keyLength: Int
    ) -> Data? {
        guard let passwordData = password.data(using: .utf8),
              let saltData = salt.data(using: .utf8) else {
            return nil
        }
        
        var derivedKeyData = Data(repeating: 0, count: keyLength)
        
        let status = derivedKeyData.withUnsafeMutableBytes { derivedKeyBytes in
            saltData.withUnsafeBytes { saltBytes in
                passwordData.withUnsafeBytes { passwordBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.bindMemory(to: Int8.self).baseAddress,
                        passwordData.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        saltData.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        iterations,
                        derivedKeyBytes.bindMemory(to: UInt8.self).baseAddress,
                        keyLength
                    )
                }
            }
        }
        
        return status == kCCSuccess ? derivedKeyData : nil
    }
    
    // MARK: - Encryption
    
    func encrypt(text: String) -> String? {
        guard let textData = text.data(using: .utf8) else {
            return nil
        }
        
        // IV
        var iv = Data(count: 16)
        let result = iv.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!)
        }
        guard result == errSecSuccess else { return nil }
        
        let bufferSize = textData.count + kCCBlockSizeAES128
        var buffer = Data(count: bufferSize)
        var numBytesEncrypted = 0
        
        let cryptStatus = key.withUnsafeBytes { keyBytes in
            iv.withUnsafeBytes { ivBytes in
                textData.withUnsafeBytes { textBytes in
                    buffer.withUnsafeMutableBytes { bufferBytes in
                        CCCrypt(
                            CCOperation(kCCEncrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            textBytes.baseAddress,
                            textData.count,
                            bufferBytes.baseAddress,
                            bufferSize,
                            &numBytesEncrypted
                        )
                    }
                }
            }
        }
        
        guard cryptStatus == kCCSuccess else { return nil }
        
        buffer.removeSubrange(numBytesEncrypted..<buffer.count)
        
        return iv.hexString + ":" + buffer.hexString
    }
    
    // MARK: - Decryption
    
    func decrypt(encryptedData: String) -> String? {
        let components = encryptedData.split(separator: ":")
        guard components.count == 2,
              let ivData = Data(hexString: String(components[0])),
              let encryptedBytes = Data(hexString: String(components[1])) else {
            return nil
        }
        
        let bufferSize = encryptedBytes.count + kCCBlockSizeAES128
        var buffer = Data(count: bufferSize)
        var numBytesDecrypted = 0
        
        let cryptStatus = key.withUnsafeBytes { keyBytes in
            ivData.withUnsafeBytes { ivBytes in
                encryptedBytes.withUnsafeBytes { encryptedBytesPtr in
                    buffer.withUnsafeMutableBytes { bufferBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            encryptedBytesPtr.baseAddress,
                            encryptedBytes.count,
                            bufferBytes.baseAddress,
                            bufferSize,
                            &numBytesDecrypted
                        )
                    }
                }
            }
        }
        
        guard cryptStatus == kCCSuccess else { return nil }
        
        buffer.removeSubrange(numBytesDecrypted..<buffer.count)
        
        return String(data: buffer, encoding: .utf8)
    }
}

// MARK: - Data Extensions

extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
    
    init?(hexString: String) {
        let length = hexString.count / 2
        var data = Data(capacity: length)
        
        for i in 0..<length {
            let start = hexString.index(hexString.startIndex, offsetBy: i * 2)
            let end = hexString.index(start, offsetBy: 2)
            let bytes = hexString[start..<end]
            
            if var byte = UInt8(bytes, radix: 16) {
                data.append(&byte, count: 1)
            } else {
                return nil
            }
        }
        
        self = data
    }
    
    var bytes: [UInt8] {
        [UInt8](self)
    }
}

extension CryptoManager {
    /// Decrypts any `hex:hex` tokens inside a payment message.
    /// Example:
    /// "Payment received 2 coins from iv:cipher iv:cipher"
    ///  -> "Payment received 2 coins from FirstName LastName"
    func decryptPaymentMessage(_ rawMessage: String?) -> String {
        guard let raw = rawMessage, !raw.isEmpty else { return "" }

        // Split message on spaces
        let parts = raw.split(separator: " ").map(String.init)

        let processed = parts.map { token -> String in
            // Check pattern like "hex:hex"
            guard token.contains(":"),
                  token.range(
                    of: #"^[0-9a-fA-F]+:[0-9a-fA-F]+$"#,
                    options: .regularExpression
                  ) != nil
            else {
                return token
            }

            // 🔐 Safe unwrap: decrypt returns String?
            guard let decrypted = self.decrypt(encryptedData: token),
                  !decrypted.isEmpty
            else {
                // If decryption fails or empty, keep original token
                return token
            }

            return decrypted
        }

        return processed.joined(separator: " ")
    }
}
