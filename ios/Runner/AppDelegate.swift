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
        switch call.method {
        case "createBiometricKey":
          result(self.createBiometricKey())
        case "validateBiometricKey":
          result(self.validateBiometricKey())
        case "deleteBiometricKey":
          result(self.deleteBiometricKey())
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
