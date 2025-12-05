import Foundation

 
struct UserAPIEndpoint{
    
    static let baseURL = "https://backendapi.byosync.in"
    static let baseURL2 = "https://byo-sync-backend-testing.vercel.app"
    
    
    // Login,Register,Phone & Email Verification
    struct Auth {
        static let userRegister = "\(baseURL)/api/v1/users/user-register"
        static let phoneOTP = "\(baseURL)/api/v1/users/phone-otp"
        static let verifyOTP = "\(baseURL)/api/v1/users/verify-otp"
        //(POST) - give name,deviceId to the api
        static let logIn = "\(baseURL)/api/v1/users/login"
        static let logOut = "\(baseURL)/api/v1/users/logout"
                    
        static let sendEmail = "\(baseURL)/api/v1/users/send-email"
        static let emailOtpVerification = "\(baseURL)/api/v1/users/email-otp-verification"
    }
    
    // (GET) Fetch Logged In User Data
    struct UserData{
        static let getUserData = "\(baseURL)/api/v1/users/get-user-data"
    }
    
    
    // Device Management
    struct UserDeviceManagement{
        //(POST) Unlinks all other devices using the primary device(Only primary device can logout others)
        static let unLinkOtherDevices = "\(baseURL)/api/v1/users/unlink-other-devices"
        // (GET) User's devices
        static let getLinkedDevices = "\(baseURL)/api/v1/users/get-user-link-devices"
        //(POST) Change primary device(using only primary device)
        static let changePrimaryDevice = "\(baseURL)/api/v1/users/change-primary-devices"
        
        static let isDeviceRegistered = "\(baseURL)/api/v1/users/is-device-register"
    }
    
    
    // Face Verification
    struct FaceVerification{
        static let verifyUser = "\(baseURL)/api/v1/users/verify-user"
    }

    // Edit Profile
    struct EditProfile {
           // For updating profile (PATCH)
           static let changeDetails = "\(baseURL)/api/v1/users/change-details"
           
           // For getting user data (GET)
           static let getUserData = "\(baseURL)/api/v1/users/get-user-data"
        
           static let changeProfilePic = "\(baseURL)/api/v1/users/change-profile-pic"
    }
    
    
    // Transaction
    struct TransactionAPI {
        // Remove the local baseURL and use the parent one
        
        static func dailyReport(date: String, type: String) -> String {
            return "\(UserAPIEndpoint.baseURL)/api/v1/recons/daily-report?date=\(date)&type=\(type)"
        }
        static func monthlyReport(month: String, year: String, type: String) -> String {
            return "\(UserAPIEndpoint.baseURL)/api/v1/recons/monthly-report?month=\(month)&year=\(year)&type=\(type)"
        }
        static func customReport(startDate: String, endDate: String, type: String) -> String {
            return "\(UserAPIEndpoint.baseURL)/api/v1/recons/custom-report?startDate=\(startDate)&endDate=\(endDate)&type=\(type)"
        }
    }
    
    // Payment Order
    struct PaymentOrder{
        static let updateOrder = "\(baseURL)/api/v1/orders/update"
    }
    struct GetUserSorted{
        static let getUserSortedbyTransaction = "\(baseURL)/api/v1/users/get-users-sorted-by-noOf-transactions-received"
    }
    
    struct Leaderboard{
        static let getRankboard = "\(baseURL)/api/v1/users/get-users-rank-board"
    }
    struct FaceScan{
        static let AddFaceId = "\(baseURL)/api/v1/users/addFaceId"
        static let GetFaceID = "\(baseURL)/api/v1/users/getFaceId"
    }
}


struct CommonEndpoint{
    static let baseURL = "https://backendapi.byosync.in"
    
    static let summaryTransactionData = "\(baseURL)/api/v1/recons/merchant-and-user-summary"
    
    static let CreateOrder = "\(baseURL)/api/v1/orders/create"
}

struct LogEndpoint{
    static let baseURL = "https://backendapi.byosync.in"
    
    static let createLogs = "\(baseURL)/api/v1/logs/create"
}
