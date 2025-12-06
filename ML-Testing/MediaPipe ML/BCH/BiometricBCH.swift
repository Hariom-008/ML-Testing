//
//  BCHBiometricFE.swift
//
//  Port of updated JS BCH fuzzy-extractor logic to Swift (SwiftUI-ready)
//  Requires: CryptoKit, and your C BCH codec linked in target
//

import Foundation
import CryptoKit

@_silgen_name("init_bch")
func c_init_bch(_ m: Int32, _ t: Int32, _ primPoly: UInt32) -> OpaquePointer?

@_silgen_name("bch_get_ecc_bits_bridge")  // <-- updated name
func c_get_ecc_bits(_ ctl: OpaquePointer?) -> Int32

@_silgen_name("encodebits_bch")
func c_encodebits_bch(_ ctl: OpaquePointer?, _ data: UnsafeMutablePointer<UInt8>!, _ ecc: UnsafeMutablePointer<UInt8>!)

@_silgen_name("decodebits_bch")
func c_decodebits_bch(_ ctl: OpaquePointer?, _ data: UnsafeMutablePointer<UInt8>!, _ recvECC: UnsafeMutablePointer<UInt8>!, _ errloc: UnsafeMutablePointer<UInt32>!) -> Int32

@_silgen_name("correctbits_bch")
func c_correctbits_bch(_ ctl: OpaquePointer?, _ databits: UnsafeMutablePointer<UInt8>!, _ errloc: UnsafeMutablePointer<UInt32>!, _ nerr: Int32)

@_silgen_name("free_bch")  // optional but recommended
func c_free_bch(_ ctl: OpaquePointer?)

// MARK: - Errors
enum BCHBiometricError: Error, LocalizedError {
    case notInitialized
    case invalidDistancesCount(expected: Int, actual: Int)
    case memory
    case codec(String)
    case missingRegistrationData
    case indexOutOfBounds
    case noDistanceArrays

    var errorDescription: String? {
        switch self {
        case .notInitialized: return "BCH module not initialized."
        case .invalidDistancesCount(let e, let a): return "Expected \(e) distances, got \(a)."
        case .memory: return "Failed to allocate native memory."
        case .codec(let m): return "BCH codec error: \(m)"
        case .missingRegistrationData: return "Missing helper or secret hash."
        case .indexOutOfBounds: return "Registration index out of bounds."
        case .noDistanceArrays : return "No distance arrays"
        }
    }
}

// MARK: - BCHBiometric (Fuzzy Extractor)
final class BCHBiometric {

    // === Parameters: keep in sync with your compiled bch_codec ===
    // NOTE: BCH_T MUST match your compiled library (JS uses 455). If it differs,
    // the library's internally computed ecc_bits will still be authoritative.
    static let NUM_DISTANCES = 316
    static let BITS_PER_DISTANCE = 8
    static let TOTAL_DATA_BITS = NUM_DISTANCES * BITS_PER_DISTANCE

    // Updated JS uses 18% max error budget for early checks (used informationally)
    static let MAX_CORRECTABLE_ERRORS = Int((Double(TOTAL_DATA_BITS) * 0.18).rounded())

    // BCH params from your JS
    static let BCH_M: Int32 = 13
    static let BCH_T: Int32 = 455 // IMPORTANT: must match your linked codec config

    // MARK: - Types
    typealias BitArray = [UInt8]

    struct RegistrationData: Codable {
        /// "0/1" string of helper = codeword XOR biometricBits
        let helper: String
        /// hex string: SHA256(secretKeyBitsString)
        let secretHash: String
        /// ISO timestamp for debugging/auditing
        let timestamp: Date
    }

    struct VerificationResult: Codable {
        let success: Bool
        let matchPercentage: Double       // 100 on exact hash match, else 0
        let registrationIndex: Int
        let hashMatch: Bool
        let storedHashPreview: String
        let recoveredHashPreview: String
        let numErrorsDetected: Int        // decoder-reported, if available
        let totalBitsCompared: Int
        let notes: String?
    }

    // MARK: - State
    private var ctl: OpaquePointer?
    private var eccBits: Int = 0
    private var n: Int = 0
    private var K: Int = 0
    private var initialized = false

    // MARK: - Init/Teardown
    func initBCH() throws {
        if initialized { return }
        guard let handle = c_init_bch(BCHBiometric.BCH_M, BCHBiometric.BCH_T, 0) else {
            throw BCHBiometricError.codec("init_bch returned null")
        }
        self.ctl = handle
        let eb = Int(c_get_ecc_bits(handle))
        self.eccBits = eb
        self.n = (1 << Int(BCHBiometric.BCH_M)) - 1
        self.K = n - eb
        self.initialized = true
    }

    // MARK: - Public API (mirrors JS)

    /// Register — single array or array-of-arrays (averaged)
    func registerBiometric(distances: [[Double]]?, single: [Double]? = nil) throws -> RegistrationData {
        try ensureInit()

        // resolve distances
        let d: [Double]
        if let arrays = distances, !arrays.isEmpty {
            d = try averageDistances(arrays)
        } else if let s = single {
            d = s
        } else {
            throw BCHBiometricError.invalidDistancesCount(expected: Self.NUM_DISTANCES, actual: 0)
        }

        // 1) distances -> bits
        let biometricBits = try distancesToBits(d)

        // 2) random secretKeyBits of length K (same as JS, K is typically ~>2k for m=13)
        let secretKeyBits = generateRandomBits(length: K)

        // 3) BCH encode → ecc; build codeword = data(K) || ecc(eccBits) = n
        let codeword = try encodeSecretKeyBCH(secretKeyBits)

        // 4) align biometric bits to n and XOR
        let alignedBiometric = alignBits(biometricBits, to: codeword.count, padWithZeros: true)
        let helperBits = xorBits(codeword, alignedBiometric)

        // 5) secretHash = SHA256(secretKeyBitsString)
        let secretBitsStr = bitArrayToString(secretKeyBits)
        let secretHashHex = sha256Hex(of: secretBitsStr)

        return RegistrationData(
            helper: bitArrayToString(helperBits),
            secretHash: secretHashHex,
            timestamp: Date()
        )
    }

    /// Verify — accepts either a single reg object or [reg] with index
    func verifyBiometric(distances: [Double],
                         registration: RegistrationData,
                         index: Int = 0) throws -> VerificationResult {
        try ensureInit()

        guard !registration.helper.isEmpty, !registration.secretHash.isEmpty else {
            throw BCHBiometricError.missingRegistrationData
        }

        // helper string -> bits
        let helperBits = bitStringToArray(registration.helper)

        // 1) distances -> bits
        let biometricBits = try distancesToBits(distances)

        // 2) codeword' = helper XOR aligned(biometricBits)
        let alignedBiometric = alignBits(biometricBits, to: helperBits.count, padWithZeros: true)
        let codewordPrime = xorBits(helperBits, alignedBiometric)

        // 3) BCH decode → secret'
        let decode = try decodeCodewordBCH(codewordPrime)
        let secretPrime = decode.correctedBits

        // 4) hash(secret') and compare
        let recoveredHash = sha256Hex(of: bitArrayToString(secretPrime))
        let isMatch = timingSafeEqHex(recoveredHash, registration.secretHash)

        return VerificationResult(
            success: isMatch,
            matchPercentage: isMatch ? 100 : 0,
            registrationIndex: index,
            hashMatch: isMatch,
            storedHashPreview: String(registration.secretHash.prefix(16)) + "...",
            recoveredHashPreview: String(recoveredHash.prefix(16)) + "...",
            numErrorsDetected: decode.numErrors,
            totalBitsCompared: secretPrime.count,
            notes: "K=\(K), eccBits=\(eccBits), n=\(n)"
        )
    }

    // MARK: - Core BCH encode/decode (1 byte per bit, like your JS/WASM port)

    private func encodeSecretKeyBCH(_ secretKeyBits: BitArray) throws -> BitArray {
        try ensureInit()

        // Input to encoder must be exactly K bits, each as a byte {0,1}
        let data = alignBits(secretKeyBits, to: K, padWithZeros: true)
        var dataBuf = data // contiguous
        var eccBuf = [UInt8](repeating: 0, count: eccBits)

        // Pointers
        let wrote = dataBuf.withUnsafeMutableBufferPointer { dataPtr -> Bool in
            eccBuf.withUnsafeMutableBufferPointer { eccPtr -> Bool in
                c_encodebits_bch(ctl, dataPtr.baseAddress!, eccPtr.baseAddress!)
                return true
            }
        }
        if !wrote { throw BCHBiometricError.memory }

        // codeword = data(K) || ecc(eccBits) == n
        return dataBuf + eccBuf
    }

    private func decodeCodewordBCH(_ codewordBits: BitArray) throws -> (correctedBits: BitArray, numErrors: Int) {
        try ensureInit()
        let cw = alignBits(codewordBits, to: n, padWithZeros: true)

        let dataBits = Array(cw[0..<K])
        let recvECC = Array(cw[K..<(K + eccBits)])

        var dataBuf = dataBits
        var eccBuf = recvECC
        var errloc = [UInt32](repeating: 0, count: Int(Self.BCH_T))

        let nerr: Int32 = dataBuf.withUnsafeMutableBufferPointer { dataPtr in
            eccBuf.withUnsafeMutableBufferPointer { eccPtr in
                errloc.withUnsafeMutableBufferPointer { errPtr in
                    c_decodebits_bch(ctl, dataPtr.baseAddress!, eccPtr.baseAddress!, errPtr.baseAddress!)
                }
            }
        }

        var corrected = dataBuf
        if nerr > 0 {
            _ = corrected.withUnsafeMutableBufferPointer { dataPtr in
                errloc.withUnsafeMutableBufferPointer { errPtr in
                    c_correctbits_bch(ctl, dataPtr.baseAddress!, errPtr.baseAddress!, nerr)
                }
            }
        }

        // Read back corrected bits (each byte is 0/1)
        corrected = corrected.map { $0 & 1 }
        return (correctedBits: corrected, numErrors: max(0, Int(nerr)))
    }

    // MARK: - Utilities (1:1 with your JS)

    private func distancesToBits(_ distances: [Double]) throws -> BitArray {
        guard distances.count == Self.NUM_DISTANCES else {
            throw BCHBiometricError.invalidDistancesCount(
                expected: Self.NUM_DISTANCES, actual: distances.count
            )
        }
        let normalized: [Int] = normalizeDistances(distances)
        var bits: BitArray = []
        bits.reserveCapacity(Self.TOTAL_DATA_BITS)
        for v in normalized {
            precondition(0...255 ~= v, "normalized distance out of range")
            for b in stride(from: 7, through: 0, by: -1) {
                bits.append(UInt8((v >> b) & 1))
            }
        }
        return bits
    }

    private func normalizeDistances(_ distances: [Double]) -> [Int] {
        guard let minVal = distances.min(), let maxVal = distances.max() else {
            return Array(repeating: 128, count: distances.count)
        }
        let range = maxVal - minVal
        if range == 0 {
            return Array(repeating: 128, count: distances.count)
        }
        return distances.map { d in
            let x = (d - minVal) / range
            return Int((x * 255.0).rounded())
        }
    }

    /// Average an array of distance arrays (ignores length-mismatched rows)
    private func averageDistances(_ arrays: [[Double]]) throws -> [Double] {
        guard let first = arrays.first else {
            throw BCHBiometricError.invalidDistancesCount(expected: Self.NUM_DISTANCES, actual: 0)
        }
        let n = first.count
        var sum = [Double](repeating: 0, count: n)
        var used = 0
        for arr in arrays where arr.count == n {
            for i in 0..<n { sum[i] += arr[i] }
            used += 1
        }
        guard used > 0 else {
            throw BCHBiometricError.invalidDistancesCount(expected: n, actual: 0)
        }
        return sum.map { $0 / Double(used) }
    }

    private func alignBits(_ bits: BitArray, to target: Int, padWithZeros: Bool) -> BitArray {
        if bits.count == target { return bits }
        if bits.count < target {
            let pad = [UInt8](repeating: 0, count: target - bits.count)
            return padWithZeros ? (bits + pad) : (pad + bits)
        }
        return Array(bits.prefix(target))
    }

    private func xorBits(_ a: BitArray, _ b: BitArray) -> BitArray {
        precondition(a.count == b.count, "xor length mismatch")
        var out = BitArray(repeating: 0, count: a.count)
        for i in 0..<a.count { out[i] = a[i] ^ b[i] }
        return out
    }

    private func generateRandomBits(length: Int) -> BitArray {
        let byteCount = (length + 7) / 8
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        var bits = BitArray()
        bits.reserveCapacity(length)
        for i in 0..<length {
            let byte = i / 8
            let bit = 7 - (i % 8)
            bits.append((bytes[byte] >> bit) & 1)
        }
        return bits
    }

    private func bitStringToArray(_ s: String) -> BitArray {
        var out = BitArray()
        out.reserveCapacity(s.count)
        for ch in s.utf8 {
            out.append(ch == 49 ? 1 : 0) // '1' == 49
        }
        return out
    }

    private func bitArrayToString(_ bits: BitArray) -> String {
        String(bits.map { $0 == 0 ? "0" : "1" })
    }

    private func sha256Hex(of string: String) -> String {
        let data = Data(string.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func timingSafeEqHex(_ a: String, _ b: String) -> Bool {
        let da = Array(a.utf8), db = Array(b.utf8)
        if da.count != db.count { return false }
        var diff: UInt8 = 0
        for i in 0..<da.count { diff |= da[i] ^ db[i] }
        return diff == 0
    }

    private func ensureInit() throws {
        if !initialized { try initBCH() }
    }
}
