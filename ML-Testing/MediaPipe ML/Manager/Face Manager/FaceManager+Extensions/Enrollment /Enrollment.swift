//
//  Enrollment.swift
//  ML-Testing
//
//  Created by Hari's Mac on 21.11.2025.
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
    
    private let key = "LocalEnrollmentRecords_v2_80Frames" // Updated key for 80 frames
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    private init() {}
    
    /// Save all 80 enrollment records
    func saveAll(_ records: [EnrollmentRecord]) {
        do {
            let data = try encoder.encode(records)
            UserDefaults.standard.set(data, forKey: key)
            UserDefaults.standard.synchronize() // Force immediate write
            print("💾 ✅ Saved \(records.count) enrollment records to local storage")
            
            // Verify save worked
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

struct EnrollmentRecord: Codable {
    let index: Int
    let helper: String
    let hashHex: String
    let hashBits: String
    let timestamp: Date
}

struct EnrollmentStore: Codable {
    let savedAt: String
    let enrollments: [EnrollmentRecord]
}

// MARK: - Enrollment Extension
extension FaceManager {
    
    /// Generate and store ALL 80 enrollment records locally
    func generateAndUploadFaceID(
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        let trimmedFrames = save316LengthDistanceArray()
        
        guard trimmedFrames.count == 80 else {
            print("❌ Expected 80 frames for enrollment, got \(trimmedFrames.count)")
            completion?(.failure(BiometricError.noDistanceArrays))
            return
        }
        
        print("\n🔐 ========== ENROLLMENT STARTED ==========")
        print("📊 Processing \(trimmedFrames.count) frames for enrollment")
        
        var records: [EnrollmentRecord] = []
        var successCount = 0
        var failureCount = 0
        
        for (index, distances) in trimmedFrames.enumerated() {
            do {
                let distancesDouble = distances.map { Double($0) }
                let reg = try BiometricBCH.registerBiometric(distances: distancesDouble)
                
                let record = EnrollmentRecord(
                    index: index,
                    helper: reg.helper,
                    hashHex: reg.hashHex,
                    hashBits: reg.hashBits,
                    timestamp: reg.timestamp
                )
                records.append(record)
                successCount += 1
                
                // Log every 10th frame for readability
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
    /// Success criteria: At least 25% of valid frames must match with error ≤ 20%
    func verifyFaceIDAgainstLocal(
        completion: @escaping (Result<BiometricBCH.VerificationResult, Error>) -> Void
    ) {
        print("\n🔍 ========== VERIFICATION STARTED ==========")
        
        // 1️⃣ Get current captured frames
        let trimmedFrames = save316LengthDistanceArray()
        
        print("📊 Captured \(trimmedFrames.count) frames total")
        
        // Separate valid and invalid frames with detailed logging
        var validFrames: [[Float]] = []
        var invalidFrameIndices: [Int] = []
        
        for (index, frame) in trimmedFrames.enumerated() {
            if frame.count == BiometricBCH.numDistances {
                validFrames.append(frame)
            } else {
                invalidFrameIndices.append(index)
                print("⚠️ Frame #\(index + 1) has \(frame.count) distances (expected \(BiometricBCH.numDistances)) - SKIPPED")
            }
        }
        
        print("✅ Valid frames: \(validFrames.count)")
        print("❌ Invalid frames: \(invalidFrameIndices.count)")
        
        // Require at least 60 valid frames (75% of 80)
        let minValidFrames = 60
        guard validFrames.count >= minValidFrames else {
            print("❌ Insufficient valid frames: got \(validFrames.count), need at least \(minValidFrames)")
            completion(.failure(BiometricError.invalidDistanceCount(
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
        var detailedResults: [(capturedIndex: Int, matched: Bool, bestError: Double, matchedStoredIndex: Int?)] = []
        
        let allowedErrorThreshold = 20.0 // 20% error = 80% match
        
        for (capturedIndex, capturedFrame) in validFrames.enumerated() {
            let capturedDistances = capturedFrame.map { Double($0) }
            
            var frameMatched = false
            var bestMatchError: Double = 100.0
            var bestMatchIndex: Int? = nil
            
            // Compare this captured frame against ALL 80 stored frames
            for (storedIndex, storedRecord) in storedRecords.enumerated() {
                do {
                    // Convert stored record to RegistrationData
                    let regData = BiometricBCH.RegistrationData(
                        helper: storedRecord.helper,
                        hashHex: storedRecord.hashHex,
                        hashBits: storedRecord.hashBits,
                        timestamp: storedRecord.timestamp
                    )
                    
                    // Verify captured frame against this stored frame
                    let result = try BiometricBCH.verifyBiometric(
                        distances: capturedDistances,
                        registrationData: [regData],
                        index: 0
                    )
                    
                    // Track best match
                    if result.errorPercentage < bestMatchError {
                        bestMatchError = result.errorPercentage
                        bestMatchIndex = storedIndex
                    }
                    
                    // If this stored frame matches with error ≤ 20%, mark as matched
                    if result.errorPercentage <= allowedErrorThreshold && result.hashMatch {
                        frameMatched = true
                        // Don't break - continue to find best match for logging
                    }
                    
                } catch {
                    // Silent failure for individual comparisons
                    continue
                }
            }
            
            // Record result for this captured frame
            if frameMatched {
                matchedFramesCount += 1
                detailedResults.append((capturedIndex, true, bestMatchError, bestMatchIndex))
                
                print("✅ Captured Frame #\(capturedIndex + 1): MATCHED")
                print("   └─ Best match: Stored Frame #\(bestMatchIndex! + 1)")
                print("   └─ Error: \(String(format: "%.2f", bestMatchError))% (threshold: ≤20%)")
            } else {
                unmatchedFramesCount += 1
                detailedResults.append((capturedIndex, false, bestMatchError, bestMatchIndex))
                
                print("❌ Captured Frame #\(capturedIndex + 1): NOT MATCHED")
                print("   └─ Best attempt: Stored Frame #\(bestMatchIndex != nil ? String(bestMatchIndex! + 1) : "N/A")")
                print("   └─ Error: \(String(format: "%.2f", bestMatchError))% (threshold: ≤20%)")
            }
            
            // Add separator every 10 frames for readability
            if (capturedIndex + 1) % 10 == 0 {
                print("\n--- Progress: \(capturedIndex + 1)/80 frames verified ---\n")
            }
        }
        
        // 4️⃣ Calculate statistics
        let totalValidFrames = validFrames.count
        let matchPercentage = (Double(matchedFramesCount) / Double(totalValidFrames)) * 100.0
        
        // Dynamic threshold: require 25% of valid frames to match
        let requiredMatches = max(Int(Double(totalValidFrames) * 0.25), 15) // At least 15 frames minimum
        let verificationPassed = matchedFramesCount >= requiredMatches
        
        // 5️⃣ Print detailed summary
        print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📊 VERIFICATION SUMMARY:")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("  Total Frames Captured: 80")
        print("  Valid Frames: \(totalValidFrames)")
        print("  Invalid Frames: \(invalidFrameIndices.count)")
        print("  ✅ Matched Frames: \(matchedFramesCount)/\(totalValidFrames) (\(String(format: "%.1f", matchPercentage))%)")
        print("  ❌ Unmatched Frames: \(unmatchedFramesCount)/\(totalValidFrames) (\(String(format: "%.1f", 100.0 - matchPercentage))%)")
        print("  📏 Required Matches: ≥\(requiredMatches) frames (25% of valid)")
        print("  🎯 Error Threshold: ≤20% per frame")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
        if verificationPassed {
            print("  🎉 RESULT: ✅ VERIFICATION PASSED")
            print("     └─ \(matchedFramesCount) frames matched (required: ≥\(requiredMatches))")
        } else {
            print("  ⛔ RESULT: ❌ VERIFICATION FAILED")
            print("     └─ Only \(matchedFramesCount) frames matched (required: ≥\(requiredMatches))")
        }
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
        
        // 6️⃣ Calculate average error for matched frames
        let matchedErrors = detailedResults.filter { $0.matched }.map { $0.bestError }
        let avgMatchedError = matchedErrors.isEmpty ? 0.0 : matchedErrors.reduce(0.0, +) / Double(matchedErrors.count)
        
        // 7️⃣ Create verification result
        let finalResult = BiometricBCH.VerificationResult(
            success: verificationPassed,
            matchPercentage: matchPercentage,
            errorPercentage: 100.0 - matchPercentage,
            numErrors: unmatchedFramesCount,
            matchCount: matchedFramesCount,
            totalBits: totalValidFrames, // Use actual valid frame count
            threshold: Double(requiredMatches),
            registrationIndex: 0,
            hashMatch: verificationPassed,
            hashBitsSimilarity: matchPercentage,
            reason: verificationPassed
                ? nil
                : "Only \(matchedFramesCount)/\(totalValidFrames) frames matched (required: ≥\(requiredMatches))"
        )
        
        print("📈 DETAILED STATISTICS:")
        print("  Average Error (Matched Frames): \(String(format: "%.2f", avgMatchedError))%")
        print("  Match Success Rate: \(String(format: "%.1f", matchPercentage))%")
        print("  Verification Status: \(verificationPassed ? "✅ PASS" : "❌ FAIL")")
        print("\n🔍 ========== VERIFICATION COMPLETED ==========\n")
        
        completion(.success(finalResult))
    }
}
