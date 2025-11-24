//
//  CloudinaryService.swift
//  ML-Testing
//
//  Created by Hari's Mac on 24.11.2025.
//
import Foundation
import Cloudinary
import UIKit

enum CloudinaryError : Swift.Error {
    case unknown
    case dataDecodingError
}

final class CloudinaryManager{
    static let shared = CloudinaryManager()
    
    // MARK: - Properties
    private let cloudinary: CLDCloudinary
    
    // 👇 Your unsigned upload preset name from Cloudinary dashboard
    private let uploadPreset: String = "unsigned_profile_upload"
    
    // MARK: - Initializer
    private init() {
        // 👇 Your Cloudinary cloud name
        let config = CLDConfiguration(cloudName: "dtf5st5gk", secure: true)
        self.cloudinary = CLDCloudinary(configuration: config)
    }
    
    // MARK: - Upload Function
    /// Uploads a UIImage to Cloudinary and returns the secure URL string
    func uploadImage(_ image: UIImage) async throws -> String {
        // Convert the UIImage to JPEG data
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
           print("❌ Data Decoding Error in Cloudinary Upload Image")
            throw CloudinaryError.dataDecodingError
        }
        
        // Perform async upload
        return try await withCheckedThrowingContinuation { continuation in
            cloudinary.createUploader().upload(
                data: imageData,
                uploadPreset: uploadPreset,
                params: CLDUploadRequestParams().setFolder("ios_frameCollections") // 👈 Folder name from your preset
            ) { response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let url = response?.secureUrl else {
                    continuation.resume(throwing: CloudinaryError.unknown)
                    return
                }
                
                print("✅ Uploaded to Cloudinary: \(url)") // Useful debug log
                continuation.resume(returning: url)
            }
        }
    }
}
