//
//  BiometricBCH.swift
//  ML-Testing
//
//  Created by Hari's Mac on 02.12.2025.
//

import Foundation
import Foundation
import CryptoKit

/// Port of the XOR-based helper-data approach from bch_integration.js
enum BiometricError: Error, LocalizedError {
    case noDistanceArrays
    case invalidDistanceCount(expected: Int, actual: Int)
    case registrationIndexOutOfRange(index: Int, count: Int)
    case missingHashBitsForErrorCalculation
    case helperAndHashBitsLengthMismatch
    case generic(_ message: String)

    var errorDescription: String? {
        switch self {
        case .noDistanceArrays:
            return "No distance arrays provided."
        case .invalidDistanceCount(let expected, let actual):
            return "Expected \(expected) distances, got \(actual)."
        case .registrationIndexOutOfRange(let index, let count):
            return "Index \(index) out of bounds (registrationData.count = \(count))."
        case .missingHashBitsForErrorCalculation:
            return "Missing hashBits data for error calculation."
        case .helperAndHashBitsLengthMismatch:
            return "Helper bits and hashBits length mismatch."
        case .generic(let message):
            return message
        }
    }
}

struct BiometricBCH {
    // MARK: - Constants (mirroring JS)
    static let numDistances = 316
    static let bitsPerDistance = 8
    static let totalDataBits = numDistances * bitsPerDistance
    /// JS uses ~20% threshold, literally `MAX_ERROR_THRESHOLD = 18;`
    static let maxErrorThresholdPercent: Double = 18.0
    
    typealias BitArray = [UInt8]
    
    // MARK: - Data Models
    
    struct RegistrationData: Codable {
        /// String of '0'/'1': helperData = distanceBits XOR hashBits
        let helper: String
        /// Hex string: SHA256(hashBitsString), same as CryptoJS.SHA256 in JS
        let hashHex: String
        /// String of '0'/'1': original random hashBits
        let hashBits: String
        /// ISO8601 timestamp (JS: `new Date().toISOString()`)
        let timestamp: Date
    }
    
    struct VerificationResult {
        let success: Bool
        let matchPercentage: Double
        let errorPercentage: Double
        let numErrors: Int
        let matchCount: Int
        let totalBits: Int
        let threshold: Double
        let registrationIndex: Int
        let hashMatch: Bool
        let hashBitsSimilarity: Double
        /// Optional reason when `success == false`
        let reason: String?
    }
    
    // MARK: - Helpers: normalization and bit conversions
    
    /// Average multiple distance arrays (like JS `averageDistances`)
    static func averageDistances(_ distanceArrays: [[Double]]) throws -> [Double] {
        guard !distanceArrays.isEmpty else {
            throw BiometricError.noDistanceArrays
        }
        
        // Always use the global constant
        let expected = BiometricBCH.numDistances
        
        var summed = Array(repeating: 0.0, count: expected)
        var countUsed = 0
        
        for (idx, arr) in distanceArrays.enumerated() {
            guard arr.count == expected else {
                print("⚠️ Distance array length mismatch at index \(idx): expected \(expected), got \(arr.count). Skipping.")
                continue
            }
            for i in 0..<expected {
                summed[i] += arr[i]
            }
            countUsed += 1
        }
        
        guard countUsed > 0 else {
            throw BiometricError.generic("No valid distance arrays after filtering mismatched lengths.")
        }
        
        return summed.map { $0 / Double(countUsed) }
    }

    
    /// Min-max normalize to [0, 255] (JS `normalizeDistances`)
    static func normalizeDistances(_ distances: [Double]) -> [Int] {
        let numDistances = distances.map { $0 }
        guard let minDist = numDistances.min(),
              let maxDist = numDistances.max() else {
            return Array(repeating: 128, count: distances.count)
        }
        
        let range = maxDist - minDist
        print("Distance range: min=\(minDist), max=\(maxDist), range=\(range)")
        
        if range == 0 {
            // all same, set to middle value
            return Array(repeating: 128, count: distances.count)
        }
        
        return numDistances.map { dist in
            let normalized = (dist - minDist) / range
            return Int(round(normalized * 255.0))
        }
    }
    
    /// distances → bits (with normalization), JS `distancesToBits` (new version)
    static func distancesToBits(_ distances: [Double]) throws -> BitArray {
        guard distances.count == numDistances else {
            throw BiometricError.invalidDistanceCount(
                expected: numDistances,
                actual: distances.count
            )
        }
        
        print("Converting distances to bits: \(numDistances) distances, \(bitsPerDistance) bits each")
        let normalized = normalizeDistances(distances)
        var bits: BitArray = []
        bits.reserveCapacity(normalized.count * bitsPerDistance)
        
        for (i, dist) in normalized.enumerated() {
            guard dist >= 0 && dist <= 255 else {
                throw BiometricError.generic(
                    "Distance \(i) must be in 0–255, got \(dist)"
                )
            }
            // 8-bit MSB-first
            for bit in stride(from: 7, through: 0, by: -1) {
                let value = (dist >> bit) & 1
                bits.append(UInt8(value))
            }
        }
        
        print("Converted \(distances.count) distances to \(bits.count) bits")
        return bits
    }
    
    /// bits → distances (from commented JS `bitsToDistances`)
    static func bitsToDistances(_ bits: BitArray) throws -> [Int] {
        guard bits.count == totalDataBits else {
            throw BiometricError.generic(
                "Expected \(totalDataBits) bits, got \(bits.count)"
            )
        }
        
        var distances: [Int] = []
        distances.reserveCapacity(numDistances)
        
        for i in 0..<numDistances {
            var dist = 0
            for bit in 0..<bitsPerDistance {
                let bitIdx = i * bitsPerDistance + bit
                dist = (dist << 1) | Int(bits[bitIdx] & 1)
            }
            distances.append(dist)
        }
        return distances
    }
    
    /// XOR two bit arrays (JS `xorBits`)
    static func xorBits(_ a: BitArray, _ b: BitArray) throws -> BitArray {
        guard a.count == b.count else {
            throw BiometricError.generic("Bit arrays must have same length")
        }
        var result = BitArray()
        result.reserveCapacity(a.count)
        for i in 0..<a.count {
            result.append((a[i] ^ b[i]) & 1)
        }
        return result
    }
    
    /// Secure random bits (JS `generateRandomBits`)
    static func generateRandomBits(length: Int) -> BitArray {
        var bits = BitArray()
        bits.reserveCapacity(length)
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<length {
            bits.append(UInt8.random(in: 0...1, using: &rng))
        }
        return bits
    }
    
    /// SHA256 hex of a string (mirrors CryptoJS.SHA256(string).toString(CryptoJS.enc.Hex))
    static func sha256Hex(of string: String) -> String {
        let data = Data(string.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    /// Convert "010101" -> [0,1,0,1,0,1]
    static func bitStringToArray(_ s: String) -> BitArray {
        return s.map { $0 == "1" ? UInt8(1) : UInt8(0) }
    }
    
    /// Convert [0,1,0,1] -> "0101"
    static func bitArrayToString(_ bits: BitArray) -> String {
        return bits.map { $0 == 0 ? "0" : "1" }.joined()
    }
    
    // MARK: - Registration (JS: `registerBiometric`)
    
    /// Register using a single distance array
    static func registerBiometric(distances: [Double]) throws -> RegistrationData {
        print("Processing distances for registration:", distances.count)
        
        // 1. distances → bits
        let distanceBits = try distancesToBits(distances)
        
        // 2. Generate random hashBits, then hashHex
        let hashBits = generateRandomBits(length: distanceBits.count)
        
        // JS: hashHex := SHA256(hashBitsString)
        let hashBitsString = bitArrayToString(hashBits)
        let hashHex = sha256Hex(of: hashBitsString)
        print("Generated hashHex:", String(hashHex.prefix(16)) + "...")
        
        // 3. helperData = distanceBits XOR hashBits
        let helperBits = try xorBits(distanceBits, hashBits)
        print("Created helperData: \(helperBits.count) bits")
        
        let helperString = bitArrayToString(helperBits)
        
        print("Registration data created:", [
            "helper": helperString.count,
            "hashHex": hashHex.count,
            "hashBits": hashBitsString.count
        ])
        
        return RegistrationData(
            helper: helperString,
            hashHex: hashHex,
            hashBits: hashBitsString,
            timestamp: Date()
        )
    }
    
    /// Register using multiple distance arrays (JS: `averageDistances` branch)
    static func registerBiometric(multipleDistances: [[Double]]) throws -> RegistrationData {
        let averaged = try averageDistances(multipleDistances)
        return try registerBiometric(distances: averaged)
    }
    
    // MARK: - Verification (JS: `verifyBiometric`)
    
    static func verifyBiometric(
        distances: [Double],
        registrationData: [RegistrationData],
        index: Int = 0
    ) throws -> VerificationResult {
        guard !registrationData.isEmpty else {
            throw BiometricError.generic("registrationData is empty.")
        }
        guard index < registrationData.count else {
            throw BiometricError.registrationIndexOutOfRange(
                index: index,
                count: registrationData.count
            )
        }
        
        let reg = registrationData[index]
        
        // Convert stored strings back to bits
        let helperBits = bitStringToArray(reg.helper)
        let storedHashHex = reg.hashHex
        let storedHashBits = bitStringToArray(reg.hashBits)
        
        print("=== VERIFICATION DEBUG ===")
        print("Helper bits length:", helperBits.count)
        print("Stored hashHex:", storedHashHex.isEmpty ? "not found" : String(storedHashHex.prefix(16)) + "...")
        print("Stored hashBits length:", storedHashBits.count)
        
        // Step 1: new distances → bits
        let newDistanceBits = try distancesToBits(distances)
        print("Converted \(distances.count) distances to \(newDistanceBits.count) bits")
        
        // Step 2: reconstruct original distance bits & compute error
        guard !storedHashBits.isEmpty,
              storedHashBits.count == helperBits.count else {
            throw BiometricError.missingHashBitsForErrorCalculation
        }
        
        print("\n=== Reconstructing original distance bits ===")
        print("Helper bits first 20:", helperBits.prefix(20).map(String.init).joined(separator: ","))
        print("Stored hashBits first 20:", storedHashBits.prefix(20).map(String.init).joined(separator: ","))
        
        // helper XOR hashBits = distanceBits
        let originalDistanceBits = try xorBits(helperBits, storedHashBits)
        print("Reconstructed original distance bits: \(originalDistanceBits.count) bits")
        
        // Error percentage between newDistanceBits and originalDistanceBits
        let minLength = min(newDistanceBits.count, originalDistanceBits.count)
        var errorCount = 0
        for i in 0..<minLength {
            if newDistanceBits[i] != originalDistanceBits[i] {
                errorCount += 1
            }
        }
        
        let errorPercentage: Double = minLength > 0
            ? (Double(errorCount) / Double(minLength)) * 100.0
            : 100.0
        print("Error percentage: \(String(format: "%.2f", errorPercentage))% (\(errorCount)/\(minLength) bits differ)")
        
        // Step 3: early reject if error too high
        if errorPercentage > maxErrorThresholdPercent {
            return VerificationResult(
                success: false,
                matchPercentage: 0,
                errorPercentage: errorPercentage,
                numErrors: errorCount,
                matchCount: 0,
                totalBits: newDistanceBits.count,
                threshold: maxErrorThresholdPercent,
                registrationIndex: index,
                hashMatch: false,
                hashBitsSimilarity: 0,
                reason: "Error too high: \(String(format: "%.2f", errorPercentage))% (max: \(maxErrorThresholdPercent)%)"
            )
        }
        
        // Step 4: reconstruct hashBits from helper & originalDistanceBits
        print("\n=== Reconstructing hashBits from helper & original distance bits ===")
        let reconstructedHashBits = try xorBits(helperBits, originalDistanceBits)
        
        // Compare reconstructed hashBits vs storedHashBits
        var hashBitsMatch = true
        var hashBitsMatchCount = 0
        let maxCheck = min(storedHashBits.count, reconstructedHashBits.count)
        for i in 0..<maxCheck {
            if storedHashBits[i] == reconstructedHashBits[i] {
                hashBitsMatchCount += 1
            } else {
                hashBitsMatch = false
            }
        }
        if !hashBitsMatch {
            print("⚠️ HashBits reconstruction mismatch, matches at \(hashBitsMatchCount)/\(maxCheck) positions")
        } else {
            print("✓ HashBits reconstruction successful - all bits match")
        }
        
        // Use storedHashBits if they match, otherwise reconstructed (same as JS)
        let newHashBits: BitArray = hashBitsMatch ? storedHashBits : reconstructedHashBits
        
        // Step 5: SHA256(newHashBitsString) to hex
        let newHashBitsString = bitArrayToString(newHashBits)
        let newHashHex = sha256Hex(of: newHashBitsString)
        print("Generated newHashHex from hashBits:", String(newHashHex.prefix(32)) + "...")
        
        // Step 6: Compare hashes
        let isHashHexMatch = (newHashHex == storedHashHex)
        
        // HashBits similarity (stored vs newHashBits)
        var hashBitsSimilarityCount = 0
        let hashBitsLength = min(storedHashBits.count, newHashBits.count)
        for i in 0..<hashBitsLength {
            if storedHashBits[i] == newHashBits[i] {
                hashBitsSimilarityCount += 1
            }
        }
        let hashBitsSimilarity = hashBitsLength > 0
            ? (Double(hashBitsSimilarityCount) / Double(hashBitsLength)) * 100.0
            : 0.0
        
        // Overall match percentage (same heuristic as JS)
        var matchPercentage: Double
        if isHashHexMatch {
            matchPercentage = 100.0
        } else {
            let errorWeight = max(0.0, 100.0 - errorPercentage)
            matchPercentage = hashBitsSimilarity * 0.7 + errorWeight * 0.3
            if matchPercentage > 99.0 {
                matchPercentage = 99.0
            }
        }
        
        let isMatch = isHashHexMatch  // strict: only exact hashHex match is "success"
        
        print("=== Hash Comparison ===")
        print("Stored hashHex:", storedHashHex.isEmpty ? "not found" : String(storedHashHex.prefix(32)) + "...")
        print("New hashHex:", String(newHashHex.prefix(32)) + "...")
        print("HashHex match:", isHashHexMatch)
        print("HashBits similarity:", String(format: "%.2f", hashBitsSimilarity) + "%")
        print("HashBits match count:", hashBitsSimilarityCount, "/", hashBitsLength)
        print("Calculated match percentage:", String(format: "%.2f", matchPercentage) + "%")
        print("Final success:", isMatch)
        
        return VerificationResult(
            success: isMatch,
            matchPercentage: (matchPercentage * 100).rounded() / 100.0, // 2 decimals
            errorPercentage: errorPercentage,
            numErrors: errorCount,
            matchCount: hashBitsSimilarityCount,
            totalBits: newDistanceBits.count,
            threshold: maxErrorThresholdPercent,
            registrationIndex: index,
            hashMatch: isHashHexMatch,
            hashBitsSimilarity: hashBitsSimilarity,
            reason: isMatch ? nil : "HashHex mismatch"
        )
    }
}
