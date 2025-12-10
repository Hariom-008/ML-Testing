//
//  LocalEnrollment.swift
//  ML-Testing
//
//  Created by Hari's Mac on 09.12.2025.
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
