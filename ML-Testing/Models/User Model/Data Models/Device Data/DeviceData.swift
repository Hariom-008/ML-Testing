import SwiftUI
// MARK: - Device Data
struct DeviceData: Codable, Identifiable {
    let id: String
    let deviceKey: String
    let deviceName: String
    let user: String
    let isPrimary: Bool
    let fcmToken: String
    let createdAt: String
    let updatedAt: String
    let v: Int
    let token: String
    
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case deviceKey
        case deviceName
        case user
        case isPrimary
        case fcmToken
        case createdAt
        case updatedAt
        case v = "__v"
        case token
    }
}


struct GetDeviceData:Codable,Identifiable{
    let id: String
    let deviceKey: String
    let deviceName: String
    let isPrimary: Bool
    let createdAt: String
    let updatedAt: String
    
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case deviceKey
        case deviceName
        case isPrimary
        case createdAt
        case updatedAt
    }
}
