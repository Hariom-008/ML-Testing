import Foundation
import SwiftUI
import Alamofire
internal import AVFoundation
import UIKit
import CryptoKit

struct RegisterUserDeviceData: Codable, Identifiable {
    let id: String
    let deviceKey: String
    let deviceKeyHash: String?
    let deviceName: String
    let user: String
    let isPrimary: Bool
    let fcmToken: String
    let deviceData: String?
    let createdAt: String
    let updatedAt: String
    let v: Int
    let token: String

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case deviceKey
        case deviceKeyHash
        case deviceName
        case user
        case isPrimary
        case fcmToken
        case deviceData
        case createdAt
        case updatedAt
        case v = "__v"
        case token
    }
}

// MARK: - Response Models
struct RegisterUserResponse: Codable {
    let statusCode: Int?
    let success: Bool
    let message: String
    let data: RegisterUserData?
}


struct RegisterUserData: Codable {
    let newUser: UserData
    let newDevice: RegisterUserDeviceData
}



struct RegisterUserRequest: Encodable {
    let firstName: String
    let lastName: String
    let email: String
    let emailHash: String
    let phoneNumber: String
    let phoneNumberHash: String
    let deviceKey: String
    let deviceKeyHash: String
    let deviceName: String
    let fcmToken: String
    let referralCode: String?
    let deviceData: String
}


// MARK: - DeviceDetails Models
struct DeviceDetails: Encodable {
    let manufacturer: String
    let model: String
    let brand: String
    let deviceName: String
    let sdkInt: Int
    let iosVersion: String
    let supportedAbis: [String]

    let cpuCoreCount: Int
    let cpuMaxFreqHz: Int?           // best-effort (may be null)

    let totalRamBytes: Int
    let totalStorageBytes: Int
    let freeStorageBytes: Int

    let frontCamera: FrontCameraDetails?
}

struct FrontCameraDetails: Encodable {
    let cameraId: String
    let focalLengthMm: Float?
    let sensorWidthMm: Float?
    let sensorHeightMm: Float?

    let pixelArrayWidth: Int?
    let pixelArrayHeight: Int?

    let horizontalFovDegrees: Double?
    let verticalFovDegrees: Double?
}

func fetchDeviceDetails() -> DeviceDetails {
    let device = UIDevice.current
    let manufacturer = "Apple"  // Static for iOS
    let model = device.model
    let brand = "Apple"         // Static for iOS
    let deviceName = device.name
    let sdkInt = Int(device.systemVersion.split(separator: ".")[0]) ?? 0
    let iosVersion = device.systemVersion
    let supportedAbis = ["arm64"]  // iOS typically supports arm64

    let cpuCoreCount = ProcessInfo.processInfo.processorCount
    let totalRamBytes = ProcessInfo.processInfo.physicalMemory
    let totalStorageBytes = FileManager.default.totalDiskSpace
    let freeStorageBytes = FileManager.default.freeDiskSpace
    
    let frontCameraDetails = fetchFrontCameraDetails()

    return DeviceDetails(
        manufacturer: manufacturer,
        model: model,
        brand: brand,
        deviceName: deviceName,
        sdkInt: sdkInt,
        iosVersion: iosVersion,
        supportedAbis: supportedAbis,
        cpuCoreCount: cpuCoreCount,
        cpuMaxFreqHz: nil,  // iOS doesn't expose this directly
        totalRamBytes: Int(totalRamBytes),
        totalStorageBytes: totalStorageBytes,
        freeStorageBytes: freeStorageBytes,
        frontCamera: frontCameraDetails
    )
}

func fetchFrontCameraDetails() -> FrontCameraDetails? {
    guard let device = AVCaptureDevice.default(for: .video) else { return nil }
    guard device.position == .front else { return nil }

    let cameraId = device.uniqueID
    let focalLengthMm = device.lensPosition // Approximation
    let sensorWidthMm: Float? = nil  // iOS does not provide this directly
    let sensorHeightMm: Float? = nil // iOS does not provide this directly

    let pixelArrayWidth: Int? = nil  // iOS does not provide this directly
    let pixelArrayHeight: Int? = nil // iOS does not provide this directly

    let horizontalFovDegrees = 70.0  // Approximation for iPhone front cameras
    let verticalFovDegrees = 55.0    // Approximation for iPhone front cameras

    return FrontCameraDetails(
        cameraId: cameraId,
        focalLengthMm: focalLengthMm,
        sensorWidthMm: sensorWidthMm,
        sensorHeightMm: sensorHeightMm,
        pixelArrayWidth: pixelArrayWidth,
        pixelArrayHeight: pixelArrayHeight,
        horizontalFovDegrees: horizontalFovDegrees,
        verticalFovDegrees: verticalFovDegrees
    )
}

extension FileManager {
    var totalDiskSpace: Int {
        if let attributes = try? self.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let space = attributes[.systemSize] as? NSNumber {
            return space.intValue
        }
        return 0
    }

    var freeDiskSpace: Int {
        if let attributes = try? self.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let freeSpace = attributes[.systemFreeSize] as? NSNumber {
            return freeSpace.intValue
        }
        return 0
    }
}

final class RegisterUserRepository {

    private let cryptoService: any CryptoService
    private let hmacGenerator = HMACGenerator.self
    
    init(cryptoService: any CryptoService) {
        self.cryptoService = cryptoService
    }

    func registerUser(
        firstName: String,
        lastName: String,
        email: String,
        phoneNumber: String,
        deviceId: String,
        deviceName: String,
        completion: @escaping (Result<APIResponse<RegisterUserData>, APIError>) -> Void
    ) {
        print("📤 [API] POST \(UserAPIEndpoint.Auth.userRegister)")

        // FCM
        var fcmToken = ""
        FCMTokenManager.shared.getFCMToken { token in fcmToken = token ?? "" }

        // Device details -> JSON String
        let deviceDetails = fetchDeviceDetails()
        let encoder = JSONEncoder()
        guard let deviceJson = try? encoder.encode(deviceDetails),
              let deviceString = String(data: deviceJson, encoding: .utf8) else {
            print("❌ Failed to encode device details")
            completion(.failure(.failedToGenerateHmac))
            return
        }

        // Request payload
        let user = RegisterUserRequest(
            firstName: cryptoService.encrypt(text: firstName) ?? "",
            lastName: cryptoService.encrypt(text: lastName) ?? "",
            email: cryptoService.encrypt(text: email) ?? "",
            emailHash: hmacGenerator.generateHMAC(jsonString: email),
            phoneNumber: cryptoService.encrypt(text: phoneNumber) ?? "",
            phoneNumberHash: hmacGenerator.generateHMAC(jsonString: phoneNumber),
            deviceKey: deviceId,
            deviceKeyHash: deviceId.isEmpty ? "" : hmacGenerator.generateHMAC(jsonString: deviceId),
            deviceName: deviceName,
            fcmToken: fcmToken,
            referralCode: nil,
            deviceData: deviceString
        )

        // Encode payload (sorted keys, no escapes)
        let encoder2 = JSONEncoder()
        encoder2.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        guard let jsonData = try? encoder2.encode(user),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            print("❌ Failed to encode request JSON")
            completion(.failure(.failedToGenerateHmac))
            return
        }

        print("📦 [API] Request body prepared: \(jsonString)")

        requestWithJSONString(
            url: UserAPIEndpoint.Auth.userRegister,
            method: .post,
            jsonString: jsonString,
            userData: user,
            completion: completion
        )
    }

    // MARK: - API Sending

    private func requestWithJSONString(
        url: String,
        method: HTTPMethod,
        jsonString: String,
        userData: RegisterUserRequest,
        completion: @escaping (Result<APIResponse<RegisterUserData>, APIError>) -> Void
    ) {
        let timestamp = String(Int(Date().timeIntervalSince1970 * 1000))
        let signature = HMACGenerator.generateHMAC(jsonString: jsonString)

        let headers: HTTPHeaders = [
            "Content-Type": "application/json",
            "x-signature": signature,
            "x-timestamp": timestamp,
            "x-nonce": timestamp,
            "x-idempotency-key": timestamp
        ]

        guard let jsonData = jsonString.data(using: .utf8),
              let requestUrl = URL(string: url) else {
            completion(.failure(.unknown))
            return
        }

        var request = URLRequest(url: requestUrl)
        request.httpMethod = method.rawValue
        request.httpBody = jsonData
        headers.dictionary.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }

        APIClient.shared.requestWithCustomBodyAndResponse(
            request,
            completion: completion
        )
    }

    // MARK: - Save session (Device Only)

    func handleSuccessfulRegistration(
        device: DeviceData,
        completion: @escaping () -> Void
    ) {
        print("📱 Saving device session…")

        UserSession.shared.setCurrentDeviceID(device.id)
        UserSession.shared.setThisDevicePrimary(device.isPrimary)

        if !device.token.isEmpty {
            UserDefaults.standard.set(device.token, forKey: "token")
        }

        print("🔐 SESSION UPDATED")
        completion()
    }
}
