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

    /// Token-only verification:
    /// - Capture ~10 frames
    /// - For each captured frame, loop over 80 stored records:
    ///       If we get even ONE token match, that frame is marked as MATCHED and we break.
    /// - Session passes if at least 5 out of 10 frames have ≥1 token match.
    func verifyFaceIDAgainstLocal(
        completion: @escaping (Result<BCHBiometric.VerificationResult, Error>) -> Void
    ) {
        print("\n🔍 ========== VERIFICATION (TOKEN-ONLY) STARTED ==========")

        // Capture current frames on calling thread (cheap)
        let trimmedFrames = VerifyFrameDistanceArray()
        print("📊 Captured \(trimmedFrames.count) frames total (raw)")

        // Filter valid frames by distance count
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

        print("✅ Valid frames (distance count OK): \(validFrames.count)")
        print("❌ Invalid frames (distance count mismatch): \(invalidFrameIndices.count)")

        // We want to work with 10 collected frames
        let requiredCollectedFrames = 10

        guard validFrames.count >= requiredCollectedFrames else {
            print("❌ Insufficient valid frames for token-only verification.")
            print("   Got \(validFrames.count), but need at least \(requiredCollectedFrames) valid frames.")

            DispatchQueue.main.async {
                completion(.failure(
                    BCHBiometricError.invalidDistancesCount(
                        expected: requiredCollectedFrames,
                        actual: validFrames.count
                    )
                ))
            }
            print("🔚 ========== VERIFICATION ABORTED (NOT ENOUGH VALID FRAMES) ==========\n")
            return
        }

        // Take only the first 10 valid frames for the token check
        let framesToUse = Array(validFrames.prefix(requiredCollectedFrames))
        print("🎯 Using first \(framesToUse.count) valid frames for TOKEN comparison.\n")

        // Load all 80 stored enrollment records
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
        print("\n🔄 Starting TOKEN-ONLY frame-by-frame verification...")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

        // Prebuild RegistrationData once for BCH (used only as hashMatch gate)
        let registrationData: [BCHBiometric.RegistrationData] = storedRecords.map {
            BCHBiometric.RegistrationData(
                helper: $0.helper,
                secretHash: $0.secretHash,
                timestamp: $0.timestamp
            )
        }

        var matchedFramesCount = 0
        var unmatchedFramesCount = 0

        // For debug: which stored index matched for each captured frame (at most 1)
        var detailedFrameMatches: [(capturedIndex: Int, matched: Bool, matchedStoredIndex: Int?)] = []

        for (capturedIndex, capturedFrame) in framesToUse.enumerated() {
            let capturedDistances = capturedFrame.map { Double($0) }

            var frameMatched = false
            var matchedStoredIndex: Int? = nil

            print("📸 Checking Captured Frame #\(capturedIndex + 1) against 80 stored tokens...")

            // Loop over all stored frames; break on FIRST token match
            for (storedIndex, reg) in registrationData.enumerated() {
                do {
                    // BCH used only as a gate via hashMatch
                    let result = try BCHShared.verifyBiometric(
                        distances: capturedDistances,
                        registration: reg,
                        index: 0
                    )

                    // If BCH can't align / decode, skip token check for this pair
                    guard result.hashMatch else {
                        continue
                    }

                    // ---------- TOKEN LAYER (ONLY DECISION SIGNAL) ----------
                    let rec = storedRecords[storedIndex]

                    let R = rec.secretHash       // stored secret hash (for this record)
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
                        matchedStoredIndex = storedIndex

                        print("   ✅ TOKEN MATCH for Captured Frame #\(capturedIndex + 1)")
                        print("      └─ Matched Stored Frame #\(storedIndex + 1)")
                        // 🔴 IMPORTANT: break on first token match for this captured frame
                        break
                    }
                    // --------------------------------------------------------

                } catch {
                    print("   ⚠️ BCH verification error for stored frame #\(storedIndex + 1): \(error)")
                    continue
                }
            }

            if frameMatched {
                matchedFramesCount += 1
                detailedFrameMatches.append((capturedIndex, true, matchedStoredIndex))

                if let idx = matchedStoredIndex {
                    print("✅ RESULT for Captured Frame #\(capturedIndex + 1): MATCHED via token (Stored Frame #\(idx + 1))")
                } else {
                    print("✅ RESULT for Captured Frame #\(capturedIndex + 1): MATCHED via token (Stored index: unknown)")
                }
            } else {
                unmatchedFramesCount += 1
                detailedFrameMatches.append((capturedIndex, false, nil))

                print("❌ RESULT for Captured Frame #\(capturedIndex + 1): NO TOKEN MATCH among 80 stored frames")
            }

            print("----------------------------------------------------\n")
        }

        // ==== Summary & aggregated result ====
        let totalUsedFrames = framesToUse.count
        let matchPercentageAcrossFrames = (Double(matchedFramesCount) / Double(totalUsedFrames)) * 100.0

        // RULE: Session passes if at least 5 frames (out of 10) get a token match
        let requiredMatches = 5
        let verificationPassed = matchedFramesCount >= requiredMatches

        print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📊 VERIFICATION SUMMARY (TOKEN-ONLY):")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("  Raw Frames Captured: \(trimmedFrames.count)")
        print("  Valid Frames (distance count OK): \(validFrames.count)")
        print("  Invalid Frames (distance count mismatch): \(invalidFrameIndices.count)")
        print("  Frames Used for Token Check: \(totalUsedFrames) (target: \(requiredCollectedFrames))")
        print("  ✅ Frames with ≥1 TOKEN MATCH: \(matchedFramesCount)/\(totalUsedFrames)  (\(String(format: "%.1f", matchPercentageAcrossFrames))%)")
        print("  ❌ Frames with NO TOKEN MATCH: \(unmatchedFramesCount)/\(totalUsedFrames)")
        print("  📏 Required Matched Frames (token): ≥\(requiredMatches) out of \(totalUsedFrames)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        if verificationPassed {
            print("  🎉 RESULT: ✅ VERIFICATION PASSED (TOKEN-ONLY)")
            print("     └─ \(matchedFramesCount) frames had matching tokens (required: ≥\(requiredMatches))")
        } else {
            print("  ⛔ RESULT: ❌ VERIFICATION FAILED (TOKEN-ONLY)")
            print("     └─ Only \(matchedFramesCount) frames had matching tokens (required: ≥\(requiredMatches))")
        }
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

        print("📈 FRAME-BY-FRAME TOKEN MATCH DETAILS:")
        for info in detailedFrameMatches {
            let frameNumber = info.capturedIndex + 1
            if info.matched, let idx = info.matchedStoredIndex {
                print("  • Captured Frame #\(frameNumber): ✅ MATCHED (Stored Frame #\(idx + 1))")
            } else {
                print("  • Captured Frame #\(frameNumber): ❌ NO TOKEN MATCH")
            }
        }

        print("\n🔍 ========== VERIFICATION (TOKEN-ONLY) COMPLETED ==========\n")

        // Aggregated result (ECC metrics unused here)
        let aggregated = BCHBiometric.VerificationResult(
            success: verificationPassed,
            matchPercentage: matchPercentageAcrossFrames, // across frames (token-only)
            registrationIndex: 0,
            hashMatch: verificationPassed,                // session-level pass/fail
            storedHashPreview: "",
            recoveredHashPreview: "",
            numErrorsDetected: 0,                         // ECC bits not used
            totalBitsCompared: 0,                         // ECC bits not used
            notes: "Token-only session verification over \(totalUsedFrames) frames; " +
                   "frames with ≥1 token match: \(matchedFramesCount); " +
                   "required ≥\(requiredMatches). BCH is used only for hashMatch gating; " +
                   "ECC bit error thresholds are not part of the decision."
        )

        DispatchQueue.main.async {
            completion(.success(aggregated))
        }
    }
}
