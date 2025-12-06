//
//  Enrollment.swift
//  ML-Testing
//
//  Updated for BCH Fuzzy Extractor (helper + secretHash)
//

import Foundation
import Alamofire

// Simple error for local enrollment flow
enum LocalEnrollmentError: Error {
    case noLocalEnrollment
    case insufficientMatchedFrames(matched: Int, required: Int)
}

// MARK: - Local enrollment cache (UserDefaults-based)
final class LocalEnrollmentCache {
    static let shared = LocalEnrollmentCache()

    // New storage key for FE format (80 frames)
    private let key = "LocalEnrollmentRecords_v3_FE_80Frames"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {}

    /// Save all 80 enrollment records
    func saveAll(_ records: [EnrollmentRecord]) {
        do {
            let data = try encoder.encode(records)
            UserDefaults.standard.set(data, forKey: key)
            UserDefaults.standard.synchronize()
            print("💾 ✅ Saved \(records.count) enrollment records to local storage")

            if let _ = UserDefaults.standard.data(forKey: key) {
                print("✅ Verified: Data exists in UserDefaults")
            } else {
                print("❌ WARNING: Data not found after save!")
            }
        } catch {
            print("❌ Failed to save enrollment records:", error)
        }
    }

    /// Load all 80 enrollment records
    func loadAll() -> [EnrollmentRecord]? {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            print("⚠️ No enrollment records found in UserDefaults")
            return nil
        }
        do {
            let records = try decoder.decode([EnrollmentRecord].self, from: data)
            print("📥 ✅ Loaded \(records.count) enrollment records from local storage")
            return records
        } catch {
            print("❌ Failed to decode enrollment records:", error)
            return nil
        }
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
        print("🧹 Cleared all enrollment records")
    }
}

/// FE-style enrollment payload: helper + secretHash only
struct EnrollmentRecord: Codable {
    let index: Int
    let helper: String          // codeword ⊕ biometricBits (as "0/1" string)
    let secretHash: String      // SHA256(secretKeyBitsString) hex
    let timestamp: Date
}

struct EnrollmentStore: Codable {
    let savedAt: String
    let enrollments: [EnrollmentRecord]
}

// MARK: - Shared BCH instance (stateful: caches init/config)
private let BCHShared = BCHBiometric()

// MARK: - Enrollment Extension
extension FaceManager {

    /// Generate and store ALL 80 enrollment records locally (helper + secretHash)
    func generateAndUploadFaceID(
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        // Distances source (assumed existing)
        let trimmedFrames = save316LengthDistanceArray()

        guard trimmedFrames.count == 80 else {
            print("❌ Expected 80 frames for enrollment, got \(trimmedFrames.count)")
            completion?(.failure(BCHBiometricError.noDistanceArrays))
            return
        }

        print("\n🔐 ========== ENROLLMENT STARTED ==========")
        print("📊 Processing \(trimmedFrames.count) frames for enrollment")

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

                let record = EnrollmentRecord(
                    index: index,
                    helper: reg.helper,
                    secretHash: reg.secretHash,
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
            completion?(.failure(LocalEnrollmentError.noLocalEnrollment))
            return
        }

        // Store all 80 records locally
        LocalEnrollmentCache.shared.saveAll(records)

        print("🎉 ========== ENROLLMENT COMPLETED ==========\n")
        completion?(.success(()))
    }
}

// MARK: - Verification Extension
extension FaceManager {

    /// Verify current captured frames against stored 80 enrollment frames
    /// Success criteria: At least 25% of valid frames must match with decoder error ≤ 20%
    func verifyFaceIDAgainstLocal(
        completion: @escaping (Result<BCHBiometric.VerificationResult, Error>) -> Void
    ) {
        print("\n🔍 ========== VERIFICATION STARTED ==========")

        // 1️⃣ Get current captured frames
        let trimmedFrames = VerifyFrameDistanceArray()
        print("📊 Captured \(trimmedFrames.count) frames total")

        // Separate valid and invalid frames with detailed logging
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

        // Require at least 5 valid frames (50% of 10)
        let minValidFrames = 5
        guard validFrames.count >= minValidFrames else {
            print("❌ Insufficient valid frames: got \(validFrames.count), need at least \(minValidFrames)")
            completion(.failure(BCHBiometricError.invalidDistancesCount(
                expected: minValidFrames,
                actual: validFrames.count
            )))
            return
        }

        // 2️⃣ Load all 80 stored enrollment records
        guard let storedRecords = LocalEnrollmentCache.shared.loadAll() else {
            print("❌ No enrollment records found in local storage")
            completion(.failure(LocalEnrollmentError.noLocalEnrollment))
            return
        }

        guard storedRecords.count == 80 else {
            print("❌ Expected 80 stored records, found \(storedRecords.count)")
            completion(.failure(LocalEnrollmentError.noLocalEnrollment))
            return
        }

        print("✅ Loaded 80 enrollment records from storage")
        print("\n🔄 Starting frame-by-frame verification...")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

        // 3️⃣ Compare each captured frame against all 80 stored frames
        var matchedFramesCount = 0
        var unmatchedFramesCount = 0
        var detailedResults: [(capturedIndex: Int, matched: Bool, bestErrorPct: Double, matchedStoredIndex: Int?)] = []

        let allowedErrorThreshold = 20.0 // ≤ 20% on BCH data bits (K)

        for (capturedIndex, capturedFrame) in validFrames.enumerated() {
            let capturedDistances = capturedFrame.map { Double($0) }

            var frameMatched = false
            var bestErrorPct: Double = 100.0
            var bestMatchIndex: Int? = nil

            for (storedIndex, storedRecord) in storedRecords.enumerated() {
                do {
                    // Build RegistrationData
                    let reg = BCHBiometric.RegistrationData(
                        helper: storedRecord.helper,
                        secretHash: storedRecord.secretHash,
                        timestamp: storedRecord.timestamp
                    )

                    // Run FE verify against this stored frame
                    let result = try BCHShared.verifyBiometric(
                        distances: capturedDistances,
                        registration: reg,
                        index: 0
                    )

                    // error% over BCH data bits = numErrorsDetected / totalBitsCompared
                    let errPct = result.totalBitsCompared > 0
                        ? (Double(result.numErrorsDetected) / Double(result.totalBitsCompared)) * 100.0
                        : 100.0

                    // Track best (lowest) error% regardless of match state
                    if errPct < bestErrorPct {
                        bestErrorPct = errPct
                        bestMatchIndex = storedIndex
                    }

                    // Count this captured frame as matched only if:
                    //   - hash recovered == stored hash (cryptographic match)
                    //   - and err% within allowed threshold
                    if result.hashMatch && errPct <= allowedErrorThreshold {
                        frameMatched = true
                        // keep looping to log best match
                    }

                } catch {
                    // Ignore any per-pair failure and continue
                    continue
                }
            }

            if frameMatched {
                matchedFramesCount += 1
                detailedResults.append((capturedIndex, true, bestErrorPct, bestMatchIndex))
                print("✅ Captured Frame #\(capturedIndex + 1): MATCHED")
                if let idx = bestMatchIndex {
                    print("   └─ Best match: Stored Frame #\(idx + 1)")
                }
                print("   └─ BCH data-bit error: \(String(format: "%.2f", bestErrorPct))% (threshold: ≤\(allowedErrorThreshold)%)")
            } else {
                unmatchedFramesCount += 1
                detailedResults.append((capturedIndex, false, bestErrorPct, bestMatchIndex))
                print("❌ Captured Frame #\(capturedIndex + 1): NOT MATCHED")
                if let idx = bestMatchIndex {
                    print("   └─ Best attempt: Stored Frame #\(idx + 1)")
                } else {
                    print("   └─ Best attempt: N/A")
                }
                print("   └─ BCH data-bit error: \(String(format: "%.2f", bestErrorPct))% (threshold: ≤\(allowedErrorThreshold)%)")
            }

            if (capturedIndex + 1) % 10 == 0 {
                print("\n--- Progress: \(capturedIndex + 1)/80 frames verified ---\n")
            }
        }

        // 4️⃣ Calculate statistics
        let totalValidFrames = validFrames.count
        let matchPercentageAcrossFrames = (Double(matchedFramesCount) / Double(totalValidFrames)) * 100.0

        // Dynamic threshold: require 25% of valid frames to match (min 15)
        let requiredMatches = max(Int(Double(totalValidFrames) * 0.25),5)
        let verificationPassed = matchedFramesCount >= requiredMatches

        // 5️⃣ Print detailed summary
        print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📊 VERIFICATION SUMMARY:")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("  Total Frames Captured: 10")
        print("  Valid Frames: \(totalValidFrames)")
        print("  Invalid Frames: \(invalidFrameIndices.count)")
        print("  ✅ Matched Frames: \(matchedFramesCount)/\(totalValidFrames) (\(String(format: "%.1f", matchPercentageAcrossFrames))%)")
        print("  ❌ Unmatched Frames: \(unmatchedFramesCount)/\(totalValidFrames) (\(String(format: "%.1f", 100.0 - matchPercentageAcrossFrames))%)")
        print("  📏 Required Matches: ≥\(requiredMatches) frames (25% of valid)")
        print("  🎯 BCH Error Threshold: ≤\(allowedErrorThreshold)% per frame")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        if verificationPassed {
            print("  🎉 RESULT: ✅ VERIFICATION PASSED")
            print("     └─ \(matchedFramesCount) frames matched (required: ≥\(requiredMatches))")
        } else {
            print("  ⛔ RESULT: ❌ VERIFICATION FAILED")
            print("     └─ Only \(matchedFramesCount) frames matched (required: ≥\(requiredMatches))")
        }
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

        // 6️⃣ Average error among matched frames (for telemetry)
        let matchedErrors = detailedResults.filter { $0.matched }.map { $0.bestErrorPct }
        let avgMatchedError = matchedErrors.isEmpty ? 0.0 : matchedErrors.reduce(0.0, +) / Double(matchedErrors.count)

        print("📈 DETAILED STATISTICS:")
        print("  Average BCH Error (Matched Frames): \(String(format: "%.2f", avgMatchedError))%")
        print("  Match Success Rate (Frames): \(String(format: "%.1f", matchPercentageAcrossFrames))%")
        print("  Verification Status: \(verificationPassed ? "✅ PASS" : "❌ FAIL")")
        print("\n🔍 ========== VERIFICATION COMPLETED ==========\n")

        // 7️⃣ Return an aggregated result using BCHBiometric.VerificationResult
        //    (We overload the fields to summarize a session across many frames.)
        let aggregated = BCHBiometric.VerificationResult(
            success: verificationPassed,
            matchPercentage: matchPercentageAcrossFrames,        // across frames
            registrationIndex: 0,
            hashMatch: verificationPassed,                       // session-level pass/fail
            storedHashPreview: "",
            recoveredHashPreview: "",
            numErrorsDetected: unmatchedFramesCount,             // number of frames that failed (telemetry)
            totalBitsCompared: totalValidFrames,                 // number of frames assessed
            notes: "Aggregated verification over \(totalValidFrames) frames; matched \(matchedFramesCount); required ≥\(requiredMatches); per-frame BCH error threshold ≤\(allowedErrorThreshold)%."
        )

        completion(.success(aggregated))
    }
}
