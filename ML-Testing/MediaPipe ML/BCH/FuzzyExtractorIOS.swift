//
//  FuzzyExtractorIOS.swift
//  ML-Testing
//
//  Created by Hari's Mac on 21.11.2025.
//

import Foundation
import CryptoKit

struct QuantizationParams {
    let bitsPerDistance: Int
    let maxDistance: Float
    let quantizationStep: Float

    static let `default` = QuantizationParams(
        bitsPerDistance: 8,
        maxDistance: 2.0,
        quantizationStep: 0.2
    )
}

struct EnrollmentRecord: Codable{
    let index: Int
    let helper: String
    let hashHex: String
    let eccBits: String
}

struct EnrollmentStore: Codable {
    let savedAt: String
    let enrollments: [EnrollmentRecord]
}

enum FuzzyExtractorIOS {
    // MARK: - Bit helpers

    static func quantizeDistances(_ distances: [Float],
                                  params: QuantizationParams = .default) -> String {
        let bitsPerDistance = params.bitsPerDistance
        let maxDistance = params.maxDistance
        let step = params.quantizationStep

        let maxLevel = min(
            (1 << bitsPerDistance) - 1,
            Int(round(maxDistance / step))
        )

        var out = ""
        out.reserveCapacity(distances.count * bitsPerDistance)

        for d in distances {
            let clamped = max(0, min(maxDistance, d))
            let level = min(maxLevel, Int(round(clamped / step)))
            let gray = level ^ (level >> 1)
            var bin = String(gray, radix: 2)
            if bin.count < bitsPerDistance {
                bin = String(repeating: "0", count: bitsPerDistance - bin.count) + bin
            }
            out.append(bin)
        }

        return out
    }

    static func padBitsToDataLength(_ bits: String, dataBits: Int) -> String {
        if bits.count == dataBits { return bits }
        if bits.count > dataBits { return String(bits.prefix(dataBits)) }
        return bits + String(repeating: "0", count: dataBits - bits.count)
    }

    static func bitStringToUInt8Array(_ bits: String) -> [UInt8] {
        var arr = [UInt8]()
        arr.reserveCapacity(bits.count)
        for ch in bits {
            arr.append(ch == "1" ? 1 : 0)
        }
        return arr
    }

    static func uint8ArrayToBitString(_ arr: [UInt8]) -> String {
        var s = ""
        s.reserveCapacity(arr.count)
        for v in arr {
            s.append(v == 0 ? "0" : "1")
        }
        return s
    }

    static func xorStrings(_ a: String, _ b: String) -> String {
        let aChars = Array(a)
        let bChars = Array(b)
        let maxLen = max(aChars.count, bChars.count)

        var out = ""
        out.reserveCapacity(maxLen)

        for i in 0..<maxLen {
            let bit1 = (i < aChars.count && aChars[i] == "1") ? 1 : 0
            let bit2 = (i < bChars.count && bChars[i] == "1") ? 1 : 0
            out.append((bit1 ^ bit2) == 1 ? "1" : "0")
        }

        return out
    }

    static func hexToBitString(_ hex: String) -> String {
        var bits = ""
        bits.reserveCapacity(hex.count * 4)
        for ch in hex {
            guard let v = Int(String(ch), radix: 16) else { continue }
            var bin = String(v, radix: 2)
            if bin.count < 4 {
                bin = String(repeating: "0", count: 4 - bin.count) + bin
            }
            bits.append(bin)
        }
        return bits
    }

    static func expandBitString(_ bitString: String, length: Int) -> String {
        guard !bitString.isEmpty else {
            return String(repeating: "0", count: length)
        }
        var out = ""
        out.reserveCapacity(length)
        while out.count < length {
            out.append(bitString)
        }
        if out.count > length {
            out = String(out.prefix(length))
        }
        return out
    }

    static func expandHashBits(_ hashHex: String, length: Int) -> String {
        let baseBits = hexToBitString(hashHex)
        return expandBitString(baseBits, length: length)
    }

    static func buildCodeword(fromBitString bits: String,
                              bch: BCHFuzzyExtractor) -> (paddedBits: String,
                                                          eccBits: String,
                                                          codeword: String)? {
        let padded = padBitsToDataLength(bits, dataBits: bch.dataBits)
        let dataBitsArray = bitStringToUInt8Array(padded)

        guard let eccArray = bch.encodeBits(sourceBits: dataBitsArray) else {
            print("❌ BCH encodeBits failed")
            return nil
        }

        let eccBits = uint8ArrayToBitString(eccArray)
        let codeword = padded + eccBits

        return (padded, eccBits, codeword)
    }

    // MARK: - The Swift equivalent of FuzzyExtractorService.generate

    static func generateEnrollment(index: Int,
                                   distances: [Float],
                                   bch: BCHFuzzyExtractor,
                                   quantParams: QuantizationParams = .default) -> EnrollmentRecord? {
        guard distances.count == 316 else {
            print("❌ generateEnrollment: expected 316 distances, got \(distances.count)")
            return nil
        }

        // 1) Quantize to bits (Gray code)
        let quantizedBits = quantizeDistances(distances, params: quantParams)

        // 2) Build codeword = paddedBits + ECC bits
        guard let codewordInfo = buildCodeword(fromBitString: quantizedBits, bch: bch) else {
            return nil
        }
        let codewordBits = codewordInfo.codeword

        // 3) SHA-256 over ASCII "0"/"1" string (exactly like Node)
        guard let codewordData = codewordBits.data(using: .utf8) else { return nil }
        let digest = SHA256.hash(data: codewordData)
        let hashHex = digest.map { String(format: "%02x", $0) }.joined()

        // 4) Expand hash bits and XOR → helper
        let expandedHashBits = expandHashBits(hashHex, length: codewordBits.count)
        let helperBits = xorStrings(codewordBits, expandedHashBits)

        return EnrollmentRecord(
            index: index,
            helper: helperBits,
            hashHex: hashHex,
            eccBits: codewordInfo.eccBits
        )
    }
}
