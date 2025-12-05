import Foundation
import FirebaseMessaging
import UIKit

final class FCMTokenManager {
    static let shared = FCMTokenManager()
    
    private var cachedToken: String?
    
    private init() {
        print("🔧 FCMTokenManager initialized")
    }
    
    // Store token when received
    func setToken(_ token: String) {
        print("💾 Caching FCM token")
        cachedToken = token
    }
    
    // Get token (will return cached or request new one)
    func getFCMToken(completion: @escaping (String?) -> Void) {
        print("🔍 Getting FCM token...")
        
        // Return cached if available
        if let cached = cachedToken {
            print("✅ Returning cached token")
            completion(cached)
            return
        }
        
        // Check if ready
        guard UIApplication.shared.isRegisteredForRemoteNotifications else {
            print("⚠️ Not registered for remote notifications")
            completion(nil)
            return
        }
        
        guard Messaging.messaging().apnsToken != nil else {
            print("⚠️ APNs token not available yet")
            completion(nil)
            return
        }
        
        // Request token
        print("📡 Requesting FCM token from Firebase...")
        Messaging.messaging().token { token, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ FCM token error: \(error.localizedDescription)")
                    completion(nil)
                    return
                }
                
                guard let token = token, !token.isEmpty else {
                    print("⚠️ FCM token empty")
                    completion(nil)
                    return
                }
                
                print("✅ FCM Token retrieved: \(token)")
                self.cachedToken = token
                completion(token)
            }
        }
    }
}
