//
//  CryptoHelpers.swift
//  ML-Testing
//
//  Created by Hari's Mac on 09.12.2025.
//
//
//import Foundation
//import Foundation
//import CryptoKit
//import Security
//
//enum TokenCryptoError: Error {
//    case hexLengthMismatch
//    case invalidHex
//}
//
///// Hex -> Data
//func dataFromHex(_ hex: String) throws -> Data {
//    let len = hex.count
//    guard len % 2 == 0 else { throw TokenCryptoError.invalidHex }
//
//    var data = Data(capacity: len / 2)
//    var index = hex.startIndex
//
//    for _ in 0..<(len / 2) {
//        let nextIndex = hex.index(index, offsetBy: 2)
//        let byteString = hex[index..<nextIndex]
//        guard let byte = UInt8(byteString, radix: 16) else {
//            throw TokenCryptoError.invalidHex
//        }
//        data.append(byte)
//        index = nextIndex
//    }
//    return data
//}
//
///// Data -> hex
//func hexFromData(_ data: Data) -> String {
//    data.map { String(format: "%02x", $0) }.joined()
//}
//
///// XOR two hex strings of equal length
//func xorHex(_ h1: String, _ h2: String) throws -> String {
//    guard h1.count == h2.count else {
//        throw TokenCryptoError.hexLengthMismatch
//    }
//
//    let d1 = try dataFromHex(h1)
//    let d2 = try dataFromHex(h2)
//
//    guard d1.count == d2.count else {
//        throw TokenCryptoError.hexLengthMismatch
//    }
//
//    var out = Data(count: d1.count)
//    for i in 0..<d1.count {
//        out[i] = d1[i] ^ d2[i]
//    }
//    return hexFromData(out)
//}
//
///// Random N bytes -> hex (k is 32 bytes here)
//func randomHex(bytes: Int = 32) throws -> String {
//    var data = Data(count: bytes)
//    let result = data.withUnsafeMutableBytes { buf in
//        SecRandomCopyBytes(kSecRandomDefault, bytes, buf.baseAddress!)
//    }
//    guard result == errSecSuccess else {
//        throw TokenCryptoError.invalidHex
//    }
//    return hexFromData(data)
//}
//
///// SHA256 over UTF-8 string -> hex
//func sha256Hex(_ input: String) -> String {
//    let data = Data(input.utf8)
//    let digest = SHA256.hash(data: data)
//    return digest.map { String(format: "%02x", $0) }.joined()
//}
