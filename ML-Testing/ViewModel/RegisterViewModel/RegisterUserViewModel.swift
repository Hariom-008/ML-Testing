import Foundation
import Combine
import UIKit

final class RegisterUserViewModel: ObservableObject {
    @Published var firstName: String = "Tester"
    @Published var lastName: String = "Man"
    @Published var email: String = "tester@gmail.com"
    @Published var phoneNumber: String = "+91888777666"
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var showError: Bool = false
   // @Published var navigateToMainTab: Bool = false
    @Published var deviceId: String = "12345678a"
    @Published var deviceName: String = "iPhone 11"
    
    private let repository: RegisterUserRepository
    
    init(cryptoService: CryptoService) {
        self.repository = RegisterUserRepository(cryptoService: cryptoService)
    }
    
    // MARK: - Validation
    var allFieldsFilled: Bool {
        !firstName.isEmpty &&
        !lastName.isEmpty &&
        !email.isEmpty &&
        !phoneNumber.isEmpty
    }
    
    var isValidEmail: Bool {
        let regex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        return NSPredicate(format:"SELF MATCHES %@", regex).evaluate(with: email)
    }
    
    var canSubmit: Bool { allFieldsFilled && isValidEmail }
    
    // MARK: - Register User
    func registerUser() {
        guard canSubmit else {
            showErrorMessage("Please fill all fields correctly.")
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        repository.registerUser(
            firstName: firstName,
            lastName: lastName,
            email: email,
            phoneNumber: phoneNumber,
            deviceId: deviceId,
            deviceName: deviceName
        ) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false
                self?.handleRegistrationResult(result)
            }
        }
    }
    
    // MARK: - Handle Result
    private func handleRegistrationResult(
        _ result: Result<APIResponse<RegisterUserData>, APIError>
    ) {
        switch result {
        case .success(let response):
            guard
                let userData = response.data?.newUser,
                let device = response.data?.newDevice
            else {
                showErrorMessage("Unexpected error: missing user/device data.")
                return
            }
            
            print("✅ Registration successful")

            // 1️⃣ Save user from backend (better than using plaintext inputs)
            let registeredUser = User(
                firstName: firstName,         // or decrypt(userData.firstName) if you later add decryption
                lastName: lastName,
                email: email,
                phoneNumber: phoneNumber,
                deviceKey: device.deviceKey,
                deviceName: device.deviceName,
                userId: userData.id,
                userDeviceId: device.id
            )
            print("RegisteredUser:\(registeredUser)")

            if !device.token.isEmpty {
                UserDefaults.standard.set(device.token, forKey: "token")
            }
            KeychainHelper.standard.save("deviceKey", forKey: device.deviceKey)
            print("-----✅ Device Key is stored in KEYCHAIN-------")

        case .failure(let error):
            showErrorMessage(error.localizedDescription)
        }
    }
    
    // MARK: - Helpers
    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
    }
    
    func clearForm() {
        firstName = ""
        lastName = ""
        email = ""
        phoneNumber = ""
        errorMessage = nil
        showError = false
       // navigateToMainTab = false
    }
}
