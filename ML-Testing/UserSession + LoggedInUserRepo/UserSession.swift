import Foundation
import Combine

final class UserSession: ObservableObject {
    static let shared = UserSession()
    
    @Published var currentUser: User?
    @Published var isEmailVerified: Bool = false
    @Published var userProfilePicture: String = ""
    @Published var currentUserDeviceID: String = ""
    @Published var thisDeviceIsPrimary: Bool = false
    @Published var wallet: Double = 0
    
    private let userDefaultsKey = "currentUser"
    private let emailVerifiedKey = "isEmailVerified"
    private let profilePictureKey = "userProfilePicture"
    private let currentUserDeviceIDKey = "currentUserDeviceID"
    private let thisDevicePrimaryKey = "thisDevicePrimaryKey"
    private let walletKey = "walletKey"
    
    
    private init(){
        loadUser()
        loadEmailVerificationStatus()
        loadProfilePicture()
        loadCurrentDeviceID()
        loadThisDevicePrimary()
        loadWalletBalance()
    }

    // MARK: - Profile Picture
    func setProfilePicture(_ urlString: String) {
        self.userProfilePicture = urlString
        UserDefaults.standard.set(urlString, forKey: profilePictureKey)
    }

    func setUserWallet(_ balance: Double){
        self.wallet = balance
        UserDefaults.standard.set(balance, forKey: walletKey)
    }
    private func loadWalletBalance(){
        self.wallet = UserDefaults.standard.double(forKey: walletKey)
        print("₹ Wallet Balance Fetched : \(wallet)")
    }
    private func loadProfilePicture() {
        self.userProfilePicture = UserDefaults.standard.string(forKey: profilePictureKey) ?? ""
    }

    // MARK: - Save and Load User
    func saveUser(_ user: User) {
        self.currentUser = user
        
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(user) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
            print("✅ User saved to session: \(user.firstName) \(user.lastName)")
        }
    }
    
    func loadUser() {
        if let savedUser = UserDefaults.standard.data(forKey: userDefaultsKey) {
            let decoder = JSONDecoder()
            if let loadedUser = try? decoder.decode(User.self, from: savedUser) {
                self.currentUser = loadedUser
                loadWalletBalance()
                print("✅ User loaded from session: \(loadedUser.firstName) \(loadedUser.lastName)")
            }
        }
    }
    
    // MARK: - Email Verification Status
    func setEmailVerified(_ verified: Bool) {
        self.isEmailVerified = verified
        UserDefaults.standard.set(verified, forKey: emailVerifiedKey)
        print("✅ Email verification status updated: \(verified)")
    }
    
    private func loadEmailVerificationStatus() {
        self.isEmailVerified = UserDefaults.standard.bool(forKey: emailVerifiedKey)
        print("✅ Email verification status loaded: \(isEmailVerified)")
    }
    
    // MARK: - Current Device ID
    func setCurrentDeviceID(_ deviceID: String) {
        self.currentUserDeviceID = deviceID
        UserDefaults.standard.set(deviceID, forKey: currentUserDeviceIDKey)
        print("✅ Current device ID saved: \(deviceID)")
    }
    
    private func loadCurrentDeviceID() {
        self.currentUserDeviceID = UserDefaults.standard.string(forKey: currentUserDeviceIDKey) ?? ""
        if !currentUserDeviceID.isEmpty {
            print("✅ Loaded current device ID: \(currentUserDeviceID)")
        } else {
            print("⚠️ No device ID found in UserDefaults yet.")
        }
    }

    // MARK: - This Device Primary
    func setThisDevicePrimary(_ isPrimary: Bool) {
        self.thisDeviceIsPrimary = isPrimary
        UserDefaults.standard.set(isPrimary, forKey: thisDevicePrimaryKey)
        print("✅ This device primary status saved: \(isPrimary)")
    }
    
    private func loadThisDevicePrimary() {
        self.thisDeviceIsPrimary = UserDefaults.standard.bool(forKey: thisDevicePrimaryKey)
        print("✅ Loaded this device primary status: \(thisDeviceIsPrimary)")
    }

    // MARK: - Clear User Session
    func clearUser() {
        self.currentUser = nil
        self.isEmailVerified = false
        self.userProfilePicture = ""
        self.currentUserDeviceID = ""
        self.thisDeviceIsPrimary = false
        
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        UserDefaults.standard.removeObject(forKey: emailVerifiedKey)
        UserDefaults.standard.removeObject(forKey: profilePictureKey)
        UserDefaults.standard.removeObject(forKey: currentUserDeviceIDKey)
        UserDefaults.standard.removeObject(forKey: thisDevicePrimaryKey)
        UserDefaults.standard.removeObject(forKey: "token")
        UserDefaults.standard.removeObject(forKey: "accountType")
        
        print("🚪 User session cleared")
    }
    
    // MARK: - Computed Properties
    var fullName: String {
        guard let user = currentUser else { return "Guest User" }
        return "\(user.firstName) \(user.lastName)"
    }
    
    var email: String {
        currentUser?.email ?? "No email"
    }
    
    var phoneNumber: String {
        currentUser?.phoneNumber ?? "No phone number"
    }
    
    var byoSyncId: String {
        guard let phone = currentUser?.phoneNumber else { return "No ID" }
        return "\(phone)@okbyosync"
    }
    
    var isLoggedIn: Bool {
        currentUser != nil
    }
}
