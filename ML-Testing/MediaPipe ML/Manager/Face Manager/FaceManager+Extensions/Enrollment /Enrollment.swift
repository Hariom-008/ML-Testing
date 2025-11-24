////
////  Enrollment.swift
////  ML-Testing
////
////  Created by Hari's Mac on 21.11.2025.
////
//
//import Foundation
//// FaceManager+Enrollment.swift
//
//import Foundation
//
//extension FaceManager{
//    /// Generates enrollments.json from first 20 frames of 101-length distances
//    func generateAndSaveEnrollmentsJSON() {
//        let trimmedFrames = save136LengthDistanceArray()
//
//        guard !trimmedFrames.isEmpty else {
//            print("❌ No trimmed frames for enrollment.")
//            return
//        }
//
//        // BCH context: distanceCount=136, bitsPerDistance=8, errorRate=0.2 (same as Node)
//        guard let bch = BCHFuzzyExtractor(
//            distanceCount: 136,
//            bitsPerDistance: QuantizationParams.default.bitsPerDistance,
//            errorRate: 0.2
//        )else{
//            print("❌ Failed to init BCH context")
//            return
//        }
//
//        var records: [EnrollmentRecord] = []
//
//        for (index, distances) in trimmedFrames.enumerated() {
//            if let record = FuzzyExtractorIOS.generateEnrollment(
//                index: index,
//                distances: distances,
//                bch: bch
//            ) {
//                records.append(record)
//            }
//        }
//
//        let isoFormatter = ISO8601DateFormatter()
//        let store = EnrollmentStore(
//            savedAt: isoFormatter.string(from: Date()),
//            enrollments: records
//        )
//
//        do {
//            let encoder = JSONEncoder()
//            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
//            let data = try encoder.encode(store)
//
//            let docsURL = FileManager.default.urls(
//                for: .documentDirectory,
//                in: .userDomainMask
//            ).first!
//
//            let fileURL = docsURL.appendingPathComponent("enrollments.json")
//
//            try data.write(to: fileURL, options: .atomic)
//            print("✅ enrollments.json saved at: \(fileURL.path)")
//        } catch {
//            print("❌ Failed to save enrollments.json: \(error)")
//        }
//    }
//}
