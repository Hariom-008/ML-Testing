//
//  KeychainHelper.swift
//  ByoSync
//
//  Created by Hari's Mac on 22.10.2025.
//

import Foundation
import Security

final class KeychainHelper {
    static let standard = KeychainHelper()
    private init() {}

    func save(_ value: String, forKey key: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    func read(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var dataTypeRef: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &dataTypeRef) == noErr,
              let data = dataTypeRef as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }
        return value
    }

    func delete(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
