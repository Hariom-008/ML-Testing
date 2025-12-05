//
//  UserData.swift
//  ByoSync
//
//  Created by Hari's Mac on 22.10.2025.
//

import Foundation

// MARK: - User Model
struct User: Codable,Equatable{
    let firstName: String
    let lastName: String
    let email: String
    let phoneNumber: String?
    let deviceKey: String?
    let deviceName: String?
    let fcmToken: String?
    let refferalCode: String?
    let userId: String?
    let userDeviceId: String?
    
    
    // Convenience initializer
    init(firstName: String, lastName: String, email: String, phoneNumber: String? = nil, deviceKey: String? = nil, deviceName: String? = nil,fcmToken:String? = nil, refferalCode: String? = nil, userId:String? = nil,userDeviceId:String? = nil) {
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.phoneNumber = phoneNumber
        self.deviceKey = deviceKey
        self.deviceName = deviceName
        self.fcmToken = fcmToken
        self.refferalCode = refferalCode
        self.userId = userId
        self.userDeviceId = userDeviceId
    }
}
struct Address: Codable {
    var address1: String
    var address2: String
    var city: String
    var state: String
    var pincode: String
}


// MARK: - User Data
struct UserData: Codable,Identifiable {
    let id: String
    let email: String
    let firstName: String
    let lastName: String
    let phoneNumber: String
   // let pattern: [String]
    let salt: String
    let faceToken: String
    let wallet: Double
    let referralCode: String
    let transactionCoins: Int
    let noOfTransactions: Int
    let noOfTransactionsReceived: Int
    let profilePic: String
    let devices: [String]
    let emailVerified: Bool
    let faceId: [String]
    let createdAt: String
    let updatedAt: String
    let v: Int
    
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case email
        case firstName
        case lastName
        case phoneNumber
        //case pattern
        case salt
        case faceToken
        case wallet
        case referralCode
        case transactionCoins
        case noOfTransactions
        case noOfTransactionsReceived
        case profilePic
        case devices
        case emailVerified
        case faceId
        case createdAt
        case updatedAt
        case v = "__v"
    }
    
    var initials: String {
           let firstInitial = firstName.first?.uppercased() ?? ""
           let lastInitial = lastName.first?.uppercased() ?? ""
           return "\(firstInitial)\(lastInitial)"
       }
}




//{
//    "statusCode": 201,
//    "data":{
//        "newUser":{
//            "email":"7ce0cd23e433bf49ac35119905c25635:dc31b44f21098694eb1021049fd46915b3bcfbb6831bc5f60773ce9ea5f5af93",
//            "emailHash":"b34a56bb50c5ecec4a09226b58dee4c74b926cdf3c3992ec91ff3bda86938b9e",
//            "firstName":"fe77d2a5331f5bfa8b4a97c070e56627:06ffce5c5a4f1c695e765da6ca2b1553",
//            "lastName":"7e43418fd5687d16edf5fdc683791dcc:a0d9994f6b8021170f5292a47236d37c",
//            "phoneNumber":"c7f180f9eebc2809e6247fc5d2ae7882:cbc72a56058ec9905f948e62964c8487",
//            "phoneNumberHash":"42d928a19ad7e0a97a34f3a1def812675cdd280cea5f6975b42e606c259be6da",
//              "pattern":[],
//              "salt":"991061",
//              "faceToken":"fe77d2a5331f5bfa8b4a97c070e56627:06ffce5c5a4f1c695e765da6ca2b1553991061",
//              "wallet":10000,
//              "referralCode":"R8PVLPZ2",
//              "transactionCoins":0,
//              "noOfTransactions":0,
//              "noOfTransactionsReceived":0,
//              "profilePic":"https://cdn-icons-png.flaticon.com/512/1144/1144709.png",
//              "devices":["69241fd0698d9f04d3e6e4b0"],
//              "emailVerified":false,
//              "_id":"69241fd0698d9f04d3e6e4ae",
//              "faceId":[],
//              "createdAt":"2025-11-24T09:05:20.081Z",
//              "updatedAt":"2025-11-24T09:05:20.124Z",
//              "__v":1
//              },
//              "newDevice":{
//                "deviceKey":"12345d",
//                "deviceKeyHash":"9000247db003ecebe75ba66f0ff36a563ae3173b9c9658565353811d0abee3d9",
//                "deviceName":"iPhone 11",
//                "user":"69241fd0698d9f04d3e6e4ae",
//                "isPrimary":true,"fcmToken":"fSk1M8RqbUzrlp8bJe6yXm:APA91bE5LN-RmvNa0X_1xlIlI9-1DJT0UUaXu8KEGAA-e0CN4dOLwKa8-6aXM5y27K2XzkUOSMgMx08oGZGW91BRQB9Gv3HWKfiCNe38rFm9DvDRjczsV-g",
//                "deviceData":"{\"brand\":\"Apple\",\"iosVersion\":\"26.1\",\"sdkInt\":26,\"deviceName\":\"iPad\",\"totalStorageBytes\":58166521856,\"supportedAbis\":[\"arm64\"],\"totalRamBytes\":4005478400,\"freeStorageBytes\":8481472512,\"cpuCoreCount\":6,\"model\":\"iPad\",\"manufacturer\":\"Apple\"}","_id":"69241fd0698d9f04d3e6e4b0",
//                "createdAt":"2025-11-24T09:05:20.092Z",
//                "updatedAt":"2025-11-24T09:05:20.103Z",
//                "__v":0,
//                "token":"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJfaWQiOiI2OTI0MWZkMDY5OGQ5ZjA0ZDNlNmU0YjAiLCJpYXQiOjE3NjM5NzUxMjAsImV4cCI6MTc5NTUxMTEyMH0.ICyIuOUjj43mWcFErHVYHEsfEAEtnAWlmyiNN-nkXfo"
//                  }
//                },
//                "message":"Successfully registered as a User",
//                "success":true
//        }
