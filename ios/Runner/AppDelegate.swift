import Flutter
import UIKit
import LocalAuthentication
import Security

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let biometricKeyAlias = "eglobal_biometric_auth_key"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller = window?.rootViewController as? FlutterViewController
    if let controller = controller {
      let hapticsChannel = FlutterMethodChannel(
        name: "com.eglobal.wallet/haptics",
        binaryMessenger: controller.binaryMessenger
      )
      hapticsChannel.setMethodCallHandler { call, result in
        guard call.method == "vibrate" else {
          result(FlutterMethodNotImplemented)
          return
        }
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.prepare()
        generator.impactOccurred()
        result(nil)
      }

      let biometricChannel = FlutterMethodChannel(
        name: "com.eglobal.wallet/biometric_key",
        binaryMessenger: controller.binaryMessenger
      )
      biometricChannel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else {
          result(false)
          return
        }
        let args = call.arguments as? [String: Any]
        switch call.method {
        case "createBiometricKey":
          result(self.createBiometricKey())
        case "authenticateWithCryptoObject":
          let title = (args?["title"] as? String) ?? "Biometric Authentication"
          self.authenticateWithCryptoObject(title: title, result: result)
        case "validateBiometricKey":
          result(self.validateBiometricKey())
        case "deleteBiometricKey":
          result(self.deleteBiometricKey())
        case "cancelBiometricPrompt":
          result(true)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func createBiometricKey() -> Bool {
    _ = deleteBiometricKey()

    var error: Unmanaged<CFError>?
    guard let accessControl = SecAccessControlCreateWithFlags(
      kCFAllocatorDefault,
      kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
      [.biometryCurrentSet],
      &error
    ) else {
      return false
    }

    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: biometricKeyAlias,
      kSecValueData as String: "eglobal_valid_credential".data(using: .utf8)!,
      kSecAttrAccessControl as String: accessControl
    ]

    let status = SecItemAdd(query as CFDictionary, nil)
    return status == errSecSuccess
  }

  private func authenticateWithCryptoObject(title: String, result: @escaping FlutterResult) {
    let context = LAContext()
    var authError: NSError?

    guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) else {
      result([
        "success": false,
        "error": authError?.localizedDescription ?? "Biometrics unavailable",
        "code": "BIOMETRIC_UNAVAILABLE"
      ])
      return
    }

    context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: title) { [weak self] success, evaluateError in
      DispatchQueue.main.async {
        guard let self = self else {
          result(["success": false, "error": "Self reference lost", "code": "SYSTEM_ERROR"])
          return
        }

        if success {
          // Perform cryptographic Keychain access bound to .biometryCurrentSet
          let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: self.biometricKeyAlias,
            kSecReturnData as String: true,
            kSecUseAuthenticationContext as String: context
          ]

          var item: CFTypeRef?
          let status = SecItemCopyMatching(query as CFDictionary, &item)

          if status == errSecSuccess || status == errSecItemNotFound {
            if status == errSecItemNotFound {
              _ = self.createBiometricKey()
            }
            result(["success": true])
          } else {
            _ = self.deleteBiometricKey()
            result([
              "success": false,
              "error": "Keychain credential invalidated",
              "code": "KEY_INVALIDATED"
            ])
          }
        } else {
          let errCode = (evaluateError as NSError?)?.code
          let codeStr = (errCode == LAError.userCancel.rawValue || errCode == LAError.systemCancel.rawValue)
            ? "USER_CANCELED"
            : (errCode == LAError.biometryLockout.rawValue ? "LOCKOUT" : "AUTHENTICATION_FAILED")

          result([
            "success": false,
            "error": evaluateError?.localizedDescription ?? "Biometric authentication failed",
            "code": codeStr
          ])
        }
      }
    }
  }

  private func validateBiometricKey() -> Bool {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: biometricKeyAlias,
      kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
      kSecReturnAttributes as String: true
    ]

    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)

    if status == errSecSuccess || status == errSecInteractionNotAllowed {
      // Key exists and is valid under biometryCurrentSet
      return true
    } else {
      // errSecItemNotFound or key invalidated by biometryCurrentSet change
      _ = deleteBiometricKey()
      return false
    }
  }

  private func deleteBiometricKey() -> Bool {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: biometricKeyAlias
    ]
    let status = SecItemDelete(query as CFDictionary)
    return status == errSecSuccess || status == errSecItemNotFound
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
