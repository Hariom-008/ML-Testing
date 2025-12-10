//
//  Enrollment.swift
//  ML-Testing
//
//  Updated for BCH Fuzzy Extractor (helper + secretHash)
//
import Foundation
import Alamofire
import CryptoKit
import Security

struct EnrollmentRecord: Codable {
    let index: Int
    let helper: String          // codeword ⊕ biometricBits (as "0/1" string)
    let secretHash: String      // R = SHA256(secretKeyBitsString) hex

    let salt: String            // 256-bit hex, per enrollment (same across 80 frames)
    let k2: String              // 256-bit hex, per frame
    let token: String           // SHA256(K || R) hex, per frame

    let timestamp: Date
}

struct EnrollmentStore: Codable {
    let savedAt: String
    let enrollments: [EnrollmentRecord]
}

// MARK: - Shared BCH instance (stateful: caches init/config)
private let BCHShared = BCHBiometric()

// MARK: - Crypto helpers for SALT / K / K1 / K2 / TOKEN

private func dataFromHex(_ hex: String) -> Data? {
    let len = hex.count
    guard len % 2 == 0 else { return nil }

    var data = Data(capacity: len / 2)
    var index = hex.startIndex

    for _ in 0..<(len / 2) {
        let nextIndex = hex.index(index, offsetBy: 2)
        let byteString = hex[index..<nextIndex]
        guard let byte = UInt8(byteString, radix: 16) else {
            return nil
        }
        data.append(byte)
        index = nextIndex
    }
    return data
}

private func hexFromData(_ data: Data) -> String {
    data.map { String(format: "%02x", $0) }.joined()
}

/// XOR two hex strings of equal length; returns nil if lengths or parsing fail.
private func xorHex(_ h1: String, _ h2: String) -> String? {
    guard h1.count == h2.count else {
        print("❌ xorHex length mismatch: h1=\(h1.count), h2=\(h2.count)")
        return nil
    }

    guard
        let d1 = dataFromHex(h1),
        let d2 = dataFromHex(h2),
        d1.count == d2.count
    else {
        print("❌ xorHex invalid hex or byte-length mismatch")
        return nil
    }

    var out = Data(count: d1.count)
    for i in 0..<d1.count {
        out[i] = d1[i] ^ d2[i]
    }
    return hexFromData(out)
}

/// Random N bytes -> hex (default 32 bytes = 256-bit)
private func randomHex(bytes: Int = 32) -> String {
    var data = Data(count: bytes)
    let result = data.withUnsafeMutableBytes { buf in
        SecRandomCopyBytes(kSecRandomDefault, bytes, buf.baseAddress!)
    }
    if result != errSecSuccess {
        fatalError("❌ Failed to generate secure random bytes")
    }
    return hexFromData(data)
}

/// SHA256 over UTF-8 string -> hex
private func sha256Hex(_ input: String) -> String {
    let data = Data(input.utf8)
    let digest = SHA256.hash(data: data)
    return digest.map { String(format: "%02x", $0) }.joined()
}

// MARK: - Enrollment Extension
extension FaceManager {

    /// Generate and store ALL 80 enrollment records locally (helper + secretHash + SALT/K2/token)
    /// plus debug-only logs for SALT / K / K1 / K2 / TOKEN for each frame.
    func generateAndUploadFaceID(
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        // Capture distances on the calling thread (cheap)
        let trimmedFrames = save316LengthDistanceArray()

        guard trimmedFrames.count == 80 else {
            print("❌ Expected 80 frames for enrollment, got \(trimmedFrames.count)")
            DispatchQueue.main.async {
                completion?(.failure(BCHBiometricError.noDistanceArrays))
            }
            return
        }

        print("\n🔐 ========== ENROLLMENT STARTED ==========")
        print("📊 Processing \(trimmedFrames.count) frames for enrollment")

        // SALT: one random 256-bit value per user enrollment (same SALT for all 80 frames)
        let saltHex = randomHex(bytes: 32)
        print("🔑 SALT (user-level 256-bit): \(saltHex)")

        var records: [EnrollmentRecord] = []
        var successCount = 0
        var failureCount = 0

        for (index, distances) in trimmedFrames.enumerated() {
            do {
                // Ensure BCH is ready (idempotent)
                try BCHShared.initBCH()

                // Convert to Double
                let distancesDouble = distances.map { Double($0) }

                // Register → helper + secretHash
                let reg = try BCHShared.registerBiometric(
                    distances: nil,
                    single: distancesDouble
                )

                // R in the diagram
                let secretHash = reg.secretHash

                // K1 = R XOR SALT
                guard let k1 = xorHex(secretHash, saltHex) else {
                    print("❌ Failed to compute K1 for frame \(index + 1)")
                    failureCount += 1
                    continue
                }

                // K: random 256-bit key, unique per frame
                let kHex = randomHex(bytes: 32)

                // K2 = K1 XOR K
                guard let k2Hex = xorHex(k1, kHex) else {
                    print("❌ Failed to compute K2 for frame \(index + 1)")
                    failureCount += 1
                    continue
                }

                // token = SHA256(K || R)
                let tokenInput = kHex + secretHash
                let tokenHex = sha256Hex(tokenInput)

                // Debug logs for this frame's crypto
                print("🔹 Frame #\(index + 1) CRYPTO DEBUG")
                print("   helper (len=\(reg.helper.count))")
                print("   R (secretHash): \(secretHash)")
                print("   SALT: \(saltHex)")
                print("   K1 = R XOR SALT: \(k1)")
                print("   K (frame random 256-bit): \(kHex)")
                print("   K2 = K1 XOR K: \(k2Hex)")
                print("   TOKEN = SHA256(K || R): \(tokenHex)")

                // Store FE + crypto data locally
                let record = EnrollmentRecord(
                    index: index,
                    helper: reg.helper,
                    secretHash: secretHash,
                    salt: saltHex,
                    k2: k2Hex,
                    token: tokenHex,
                    timestamp: reg.timestamp
                )

                records.append(record)
                successCount += 1

                if (index + 1) % 10 == 0 {
                    print("✅ Frame \(index + 1)/80 processed successfully")
                }

            } catch {
                failureCount += 1
                print("❌ Failed to register frame \(index): \(error)")
            }
        }

        print("\n📊 ENROLLMENT SUMMARY:")
        print("  ✅ Successfully processed: \(successCount)/80 frames")
        print("  ❌ Failed: \(failureCount)/80 frames")

        guard records.count == 80 else {
            print("❌ Enrollment failed: Only \(records.count) records generated, need 80")

            DispatchQueue.main.async {
                completion?(.failure(LocalEnrollmentError.noLocalEnrollment))
            }
            return
        }

        // Store all 80 records locally (helper + R + SALT + K2 + token)
        LocalEnrollmentCache.shared.saveAll(records)

        print("🎉 ========== ENROLLMENT COMPLETED ==========\n")

        DispatchQueue.main.async {
            completion?(.success(()))
        }
    }
}
// MARK: - Verification Extension
extension FaceManager {

    /// Verify current captured frames against stored 80 enrollment frames.
    ///
    /// For a frame to count as MATCHED:
    ///   1. BCH hashMatch == true
    ///   2. BCH error% <= allowedErrorThreshold
    ///   3. tokenPrime == stored token (using SALT + K2 + R)
    /// Success criteria (session-level): At least 25% of valid frames must match.
    func verifyFaceIDAgainstLocal(
        completion: @escaping (Result<BCHBiometric.VerificationResult, Error>) -> Void
    ) {
        print("\n🔍 ========== VERIFICATION STARTED ==========")

        // Capture current frames on calling thread (cheap)
        let trimmedFrames = VerifyFrameDistanceArray()
        print("📊 Captured \(trimmedFrames.count) frames total")

        // Filter valid frames
        var validFrames: [[Float]] = []
        var invalidFrameIndices: [Int] = []

        for (index, frame) in trimmedFrames.enumerated() {
            if frame.count == BCHBiometric.NUM_DISTANCES {
                validFrames.append(frame)
            } else {
                invalidFrameIndices.append(index)
                print("⚠️ Frame #\(index + 1) has \(frame.count) distances (expected \(BCHBiometric.NUM_DISTANCES)) - SKIPPED")
            }
        }

        print("✅ Valid frames: \(validFrames.count)")
        print("❌ Invalid frames: \(invalidFrameIndices.count)")

        // Require at least 5 valid frames
        let minValidFrames = 5
        guard validFrames.count >= minValidFrames else {
            print("❌ Insufficient valid frames: got \(validFrames.count), need at least \(minValidFrames)")

            DispatchQueue.main.async {
                completion(.failure(BCHBiometricError.invalidDistancesCount(
                    expected: minValidFrames,
                    actual: validFrames.count
                )))
            }
            return
        }

        // Load all 80 stored enrollment records (now include salt / k2 / token)
        guard let storedRecords = LocalEnrollmentCache.shared.loadAll() else {
            print("❌ No enrollment records found in local storage")

            DispatchQueue.main.async {
                completion(.failure(LocalEnrollmentError.noLocalEnrollment))
            }
            return
        }

        guard storedRecords.count == 80 else {
            print("❌ Expected 80 stored records, found \(storedRecords.count)")

            DispatchQueue.main.async {
                completion(.failure(LocalEnrollmentError.noLocalEnrollment))
            }
            return
        }

        print("✅ Loaded 80 enrollment records from storage")
        print("\n🔄 Starting frame-by-frame verification (BCH + TOKEN)...")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

        // Prebuild RegistrationData once for BCH
        let registrationData: [BCHBiometric.RegistrationData] = storedRecords.map {
            BCHBiometric.RegistrationData(
                helper: $0.helper,
                secretHash: $0.secretHash,
                timestamp: $0.timestamp
            )
        }

        let allowedErrorThreshold = 20.0

        var matchedFramesCount = 0
        var unmatchedFramesCount = 0
        var detailedResults: [(capturedIndex: Int, matched: Bool, bestErrorPct: Double, matchedStoredIndex: Int?)] = []

        // Toggle to print full 10×80 matrix of match percentages if you want
        let debugPrintAllPairs = false     // set true if you want every pair printed
        let debugPrintOnlyMatches = true   // keep detailed logs for matches

        for (capturedIndex, capturedFrame) in validFrames.enumerated() {
            let capturedDistances = capturedFrame.map { Double($0) }

            var frameMatched = false
            var bestErrorPct: Double = 100.0
            var bestMatchIndex: Int? = nil

            // Collect all matches under threshold (BCH + token)
            var matchesWithinThreshold: [(storedIndex: Int, errorPct: Double)] = []

            // Optional: collect all pair errors if you want full 10×80 matrix logging
            var allPairErrors: [Int: Double] = [:]

            for (storedIndex, reg) in registrationData.enumerated() {
                do {
                    let result = try BCHShared.verifyBiometric(
                        distances: capturedDistances,
                        registration: reg,
                        index: 0
                    )

                    let errPct = result.totalBitsCompared > 0
                        ? (Double(result.numErrorsDetected) / Double(result.totalBitsCompared)) * 100.0
                        : 100.0

                    // Track best (lowest) error% regardless of match state
                    if errPct < bestErrorPct {
                        bestErrorPct = errPct
                        bestMatchIndex = storedIndex
                    }

                    // Keep full matrix error if desired
                    allPairErrors[storedIndex] = errPct

                    // ---------- TOKEN LAYER ----------
                    // Only bother with token if BCH hash + error threshold are OK
                    if result.hashMatch && errPct <= allowedErrorThreshold {
                        let rec = storedRecords[storedIndex]

                        let R = rec.secretHash
                        let saltHex = rec.salt
                        let k2Hex = rec.k2
                        let storedToken = rec.token

                        // K1' = R XOR SALT
                        guard let k1Prime = xorHex(R, saltHex) else {
                            print("   ⚠️ Failed to compute K1' for stored frame #\(storedIndex + 1)")
                            continue
                        }

                        // K_recovered = K1' XOR K2
                        guard let kRecovered = xorHex(k1Prime, k2Hex) else {
                            print("   ⚠️ Failed to compute K (recovered) for stored frame #\(storedIndex + 1)")
                            continue
                        }

                        // token' = SHA256(K_recovered || R)
                        let tokenPrime = sha256Hex(kRecovered + R)
                        let tokenMatch = (tokenPrime == storedToken)

                        if tokenMatch {
                            frameMatched = true
                            matchesWithinThreshold.append((storedIndex: storedIndex, errorPct: errPct))
                        } else {
                            print("   ⚠️ TOKEN MISMATCH for stored frame #\(storedIndex + 1) despite BCH match")
                            print("      tokenPrime: \(tokenPrime.prefix(16))...")
                            print("      storedToken: \(storedToken.prefix(16))...")
                        }
                    }
                    // ---------------------------------

                } catch {
                    // Ignore per-pair failure and continue
                    continue
                }
            }

            // ==== Per-frame logging ====
            if frameMatched {
                matchedFramesCount += 1
                detailedResults.append((capturedIndex, true, bestErrorPct, bestMatchIndex))

                print("✅ Captured Frame #\(capturedIndex + 1): MATCHED (BCH + TOKEN)")
                if let idx = bestMatchIndex {
                    print("   └─ Best match: Stored Frame #\(idx + 1)")
                }
                print("   └─ Best BCH data-bit error: \(String(format: "%.2f", bestErrorPct))% (threshold: ≤\(allowedErrorThreshold)%)")

                if debugPrintOnlyMatches {
                    if matchesWithinThreshold.count > 1 {
                        print("   ├─ Stored frames matched (BCH + TOKEN, ≤\(allowedErrorThreshold)% error):")
                        for m in matchesWithinThreshold {
                            let matchPct = max(0.0, 100.0 - m.errorPct)
                            print("   │   • Stored Frame #\(m.storedIndex + 1): " +
                                  "\(String(format: "%.2f", matchPct))% match " +
                                  "(error: \(String(format: "%.2f", m.errorPct))%)")
                        }
                    } else if let m = matchesWithinThreshold.first {
                        let matchPct = max(0.0, 100.0 - m.errorPct)
                        print("   └─ Stored Frame #\(m.storedIndex + 1): " +
                              "\(String(format: "%.2f", matchPct))% match " +
                              "(error: \(String(format: "%.2f", m.errorPct))%)")
                    }
                }

            } else {
                unmatchedFramesCount += 1
                detailedResults.append((capturedIndex, false, bestErrorPct, bestMatchIndex))

                print("❌ Captured Frame #\(capturedIndex + 1): NOT MATCHED (BCH + TOKEN)")
                if let idx = bestMatchIndex {
                    print("   └─ Best attempt: Stored Frame #\(idx + 1)")
                } else {
                    print("   └─ Best attempt: N/A")
                }
                print("   └─ BCH data-bit error (best): \(String(format: "%.2f", bestErrorPct))% (threshold: ≤\(allowedErrorThreshold)%)")
            }

            // 🔎 Optional: print full 10×80 matrix for this frame
            if debugPrintAllPairs {
                print("   📋 All stored-frame match percents for Captured Frame #\(capturedIndex + 1):")
                let sortedIndices = allPairErrors.keys.sorted()
                for idx in sortedIndices {
                    if let errPct = allPairErrors[idx] {
                        let matchPct = max(0.0, 100.0 - errPct)
                        print("   │   • Stored Frame #\(idx + 1): " +
                              "\(String(format: "%.2f", matchPct))% match " +
                              "(error: \(String(format: "%.2f", errPct))%)")
                    }
                }
            }

            if (capturedIndex + 1) % 10 == 0 {
                print("\n--- Progress: \(capturedIndex + 1)/\(validFrames.count) captured frames verified ---\n")
            }
        }

        // ==== Summary & aggregated result ====

        let totalValidFrames = validFrames.count
        let matchPercentageAcrossFrames = (Double(matchedFramesCount) / Double(totalValidFrames)) * 100.0

        // Require 25% of valid frames to match, minimum 5
        let requiredMatches = max(Int(Double(totalValidFrames) * 0.25), 5)
        let verificationPassed = matchedFramesCount >= requiredMatches

        print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📊 VERIFICATION SUMMARY (BCH + TOKEN):")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("  Total Frames Captured: \(trimmedFrames.count)")
        print("  Valid Frames: \(totalValidFrames)")
        print("  Invalid Frames: \(invalidFrameIndices.count)")
        print("  ✅ Matched Frames (full): \(matchedFramesCount)/\(totalValidFrames) (\(String(format: "%.1f", matchPercentageAcrossFrames))%)")
        print("  ❌ Unmatched Frames: \(unmatchedFramesCount)/\(totalValidFrames) (\(String(format: "%.1f", 100.0 - matchPercentageAcrossFrames))%)")
        print("  📏 Required Matches: ≥\(requiredMatches) frames (25% of valid)")
        print("  🎯 BCH Error Threshold: ≤\(allowedErrorThreshold)% per frame")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        if verificationPassed {
            print("  🎉 RESULT: ✅ VERIFICATION PASSED (BCH + TOKEN)")
            print("     └─ \(matchedFramesCount) frames matched (required: ≥\(requiredMatches))")
        } else {
            print("  ⛔ RESULT: ❌ VERIFICATION FAILED")
            print("     └─ Only \(matchedFramesCount) frames matched (required: ≥\(requiredMatches))")
        }
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

        let matchedErrors = detailedResults.filter { $0.matched }.map { $0.bestErrorPct }
        let avgMatchedError = matchedErrors.isEmpty ? 0.0 : matchedErrors.reduce(0.0, +) / Double(matchedErrors.count)

        print("📈 DETAILED STATISTICS:")
        print("  Average BCH Error (Matched Frames): \(String(format: "%.2f", avgMatchedError))%")
        print("  Match Success Rate (Frames, full): \(String(format: "%.1f", matchPercentageAcrossFrames))%")
        print("  Verification Status: \(verificationPassed ? "✅ PASS" : "❌ FAIL")")
        print("\n🔍 ========== VERIFICATION COMPLETED ==========\n")

        let aggregated = BCHBiometric.VerificationResult(
            success: verificationPassed,
            matchPercentage: matchPercentageAcrossFrames,        // across frames (BCH + token)
            registrationIndex: 0,
            hashMatch: verificationPassed,                       // session-level pass/fail
            storedHashPreview: "",
            recoveredHashPreview: "",
            numErrorsDetected: unmatchedFramesCount,             // number of frames that failed (telemetry)
            totalBitsCompared: totalValidFrames,                 // number of frames assessed
            notes: "Aggregated verification over \(totalValidFrames) frames; matched \(matchedFramesCount); required ≥\(requiredMatches); per-frame BCH error threshold ≤\(allowedErrorThreshold)%. Includes token check using SALT + K2 + R."
        )

        DispatchQueue.main.async {
            completion(.success(aggregated))
        }
    }
}

