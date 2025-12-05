//
//  BCH.swift
//  ML-Testing
//
//  Created by Hari's Mac on 02.12.2025.
//

import Foundation
import Foundation

// MARK: - Registration data from /users/getFaceId

struct RegistrationRecord: Codable, Identifiable {
    // You can align these with your actual JSON
    var id: String?            // server id if present
    let helper: String         // bitstring "010101..."
    let ecc: String?           // ECC helper data if you store it
    let r: String?             // random seed / codeword identifier
    let hashHex: String        // stored hash

    // Conform to Identifiable nicely
    var uuid: UUID = UUID()
    var identifiableId: String { id ?? uuid.uuidString }

    enum CodingKeys: String, CodingKey {
        case id
        case helper
        case ecc
        case r
        case hashHex
    }
}

// Try to mirror the JS logic:
// const faceData = response.data?.faceData || response.data?.data?.faceData || response.data;
struct FaceIdResponse: Codable {
    let faceData: [RegistrationRecord]?
    let data: NestedData?

    struct NestedData: Codable {
        let faceData: [RegistrationRecord]?
    }
}

// MARK: - BCH per-frame match result

struct BCHFrameMatchResult {
    let success: Bool
    let matchPercentage: Double
    let errorPercentage: Double?
    let numErrors: Int?
    let hashBitsSimilarity: Double?
    let frameIndex: Int
    let registrationIndex: Int
    let registrationId: String?
}

// MARK: - Overall verification summary

struct BCHVerificationSummary {
    let success: Bool
    let successRate: Double
    let successfulFrames: Int
    let totalFrames: Int
    let processedFrames: Int
    let bestMatch: BCHFrameMatchResult?
    let allFrameResults: [BCHFrameMatchResult]
    let isComplete: Bool
}
