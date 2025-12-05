//
//  Enrollment.swift
//  ML-Testing
//
//  Created by Hari's Mac on 21.11.2025.
//


import Foundation
import Alamofire
import Foundation

// Simple error for local enrollment flow
enum LocalEnrollmentError: Error {
    case noLocalEnrollment
}

// MARK: - Local enrollment cache (UserDefaults-based)
final class LocalEnrollmentCache {
    static let shared = LocalEnrollmentCache()
    
    private let key = "LocalEnrollmentRecord_v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    private init() {}
    
    func save(_ record: EnrollmentRecord) {
        do {
            let data = try encoder.encode(record)
            UserDefaults.standard.set(data, forKey: key)
            print("💾 Saved local enrollment (index: \(record.index))")
        } catch {
            print("❌ Failed to save local enrollment:", error)
        }
    }
    
    func load() -> EnrollmentRecord? {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            print("⚠️ No local enrollment found in UserDefaults")
            return nil
        }
        do {
            let record = try decoder.decode(EnrollmentRecord.self, from: data)
            print("📥 Loaded local enrollment (index: \(record.index))")
            return record
        } catch {
            print("❌ Failed to decode local enrollment:", error)
            return nil
        }
    }
    
    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
        print("🧹 Cleared local enrollment")
    }
}


struct EnrollmentRecord: Codable {
    let index: Int
    let helper: String
    let hashHex: String
    let hashBits: String
    //let r: String
    let timestamp: Date
}

struct EnrollmentStore: Codable {
    let savedAt: String
    let enrollments: [EnrollmentRecord]
}

extension FaceManager {
    
    /// 1️⃣ Generate enrollment data from recorded frames
    /// 2️⃣ Pick the first successful enrollment
    /// 3️⃣ Store it LOCALLY instead of sending to backend (temporary POC).
    func generateAndUploadFaceID(
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        let trimmedFrames = save316LengthDistanceArray()
        
        guard !trimmedFrames.isEmpty else {
            print("❌ No trimmed frames for enrollment.")
            completion?(.failure(BiometricError.noDistanceArrays))
            return
        }
        
        var records: [EnrollmentRecord] = []
        
        for (index, distances) in trimmedFrames.enumerated() {
            do {
                let distancesDouble = distances.map { Double($0) }
                let reg = try BiometricBCH.registerBiometric(distances: distancesDouble)
                
                print("===== Frame \(index) =====")
                print("helper (bits): \(reg.helper.prefix(80))\(reg.helper.count > 80 ? "..." : "")")
                print("hashHex: \(reg.hashHex)")
                print("hashBits: \(reg.hashBits.prefix(80))\(reg.hashBits.count > 80 ? "..." : "")")
                print("timestamp: \(reg.timestamp)")
                
                let record = EnrollmentRecord(
                    index: index,
                    helper: reg.helper,
                    hashHex: reg.hashHex,
                    hashBits: reg.hashBits,
                    timestamp: reg.timestamp
                )
                records.append(record)
            } catch {
                print("❌ Failed to register frame \(index): \(error)")
            }
        }
        
        guard let first = records.first else {
            print("❌ No enrollment records generated.")
            completion?(.failure(LocalEnrollmentError.noLocalEnrollment))
            return
        }
        
        // 🔐 TEMP: store locally (POC) instead of sending to backend
        LocalEnrollmentCache.shared.save(first)
        print("✅ Stored local enrollment (index: \(first.index))")
        completion?(.success(()))
        
        // ⬇️ When you want backend again, re-enable this block and remove local-only path
        /*
        let repo = FaceIDRepository()
        let request = RequestFaceIdAPI(
            helper: first.helper,
            hashHex: first.hashHex,
            hashBits: first.hashBits
        )
        
        repo.uploadFaceID(request) { result in
            switch result {
            case .success:
                print("✅ FaceID upload successful for frame index \(first.index)")
                completion?(.success(()))
            case .failure(let error):
                print("❌ FaceID upload failed:", error)
                completion?(.failure(error))
            }
        }
        */
    }
}
extension FaceManager {
    
    /// Captures current 316-distance frames and verifies against
    /// the locally stored enrollment (no backend).
    ///
    /// Uses the same BCH pipeline with a 20% error tolerance
    /// (≈ 80% match) like your backend version.
    func verifyFaceIDAgainstLocal(
        completion: @escaping (Result<BiometricBCH.VerificationResult, Error>) -> Void
    ) {
        // 1️⃣ Get current captured frames (each is [Float] of 316 distances)
        let trimmedFrames = save316LengthDistanceArray()
        
        print("🔍 Local verify: got \(trimmedFrames.count) frames, lengths = \(trimmedFrames.map { $0.count })")
        
        // Keep only frames with the correct length
        let validFrames = trimmedFrames.filter { $0.count == BiometricBCH.numDistances }
        
        guard !validFrames.isEmpty else {
            print("❌ No valid frames with \(BiometricBCH.numDistances) distances.")
            completion(.failure(BiometricError.invalidDistanceCount(
                expected: BiometricBCH.numDistances,
                actual: trimmedFrames.first?.count ?? 0
            )))
            return
        }
        
        // 2️⃣ Load enrollment from local cache
        guard let localRecord = LocalEnrollmentCache.shared.load() else {
            print("❌ No local enrollment record found.")
            completion(.failure(LocalEnrollmentError.noLocalEnrollment))
            return
        }
        
        // 3️⃣ Convert [[Float]] -> [[Double]] using *valid* frames only
        let doubleFrames: [[Double]] = validFrames.map { frame in
            frame.map { Double($0) }
        }
        
        // 4️⃣ Average distances across frames
        let averagedDistances: [Double]
        do {
            averagedDistances = try BiometricBCH.averageDistances(doubleFrames)
        } catch {
            print("❌ Failed to average distances:", error)
            completion(.failure(error))
            return
        }
        
        // 5️⃣ Bridge local record -> BiometricBCH.RegistrationData
        let regData = BiometricBCH.RegistrationData(
            helper: localRecord.helper,
            hashHex: localRecord.hashHex,
            hashBits: localRecord.hashBits,
            timestamp: localRecord.timestamp
        )
        
        do {
            // 6️⃣ Run BCH verification using the averaged distances
            let rawResult = try BiometricBCH.verifyBiometric(
                distances: averagedDistances,
                registrationData: [regData],
                index: 0
            )
            
            // 7️⃣ App-level error tolerance: 20%
            let allowedError = 20.0
            let passed = (rawResult.errorPercentage <= allowedError) && rawResult.hashMatch
            
            let adjustedResult = BiometricBCH.VerificationResult(
                success: passed,
                matchPercentage: rawResult.matchPercentage,
                errorPercentage: rawResult.errorPercentage,
                numErrors: rawResult.numErrors,
                matchCount: rawResult.matchCount,
                totalBits: rawResult.totalBits,
                threshold: allowedError,
                registrationIndex: rawResult.registrationIndex,
                hashMatch: rawResult.hashMatch,
                hashBitsSimilarity: rawResult.hashBitsSimilarity,
                reason: passed
                    ? nil
                    : (rawResult.reason ?? "Error > \(allowedError)% or hash mismatch")
            )
            
            print("🔍 Local verification result:")
            print("  - success: \(adjustedResult.success)")
            print("  - error %: \(adjustedResult.errorPercentage)")
            print("  - hashMatch: \(adjustedResult.hashMatch)")
            print("  - hashBitsSimilarity: \(adjustedResult.hashBitsSimilarity)")
            print("  - match %: \(adjustedResult.matchPercentage)")
            
            completion(.success(adjustedResult))
            
        } catch {
            print("❌ BCH verification (local) failed:", error)
            completion(.failure(error))
        }
    }
}
