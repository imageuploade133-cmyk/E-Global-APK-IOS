# E-Global Wallet Mobile Application – Technical Specification & Architecture

## 1. Software Requirements Specification (SRS)

### 1.1 Introduction
The E-Global Wallet Mobile Application is a high-performance, ultra-secure, and cross-platform mobile wrapper and extension for the E-Global Wallet web platform (`https://e-global-197077.vercel.app/`). The application is designed to provide a truly native-feeling, immersive experience on Android (mobiles & tablets), iOS (iPhones & iPads), and macOS devices, ensuring deep platform integration such as Biometric Authentication, Secure File Downloads/Uploads, Offline Resilience, and advanced Permission Management.

### 1.2 Scope
The scope of this project is to develop a production-grade Flutter codebase utilizing the latest stable Flutter & Dart versions. It will seamlessly integrate `flutter_inappwebview` with customized platform native features while maintaining strict alignment with the OWASP Mobile Application Security Verification Standard (MASVS).

---

## 2. Functional Requirements

### 2.1 Immersive Hybrid Rendering
* **Web Rendering Engine**: Seamless integration of `flutter_inappwebview` with optimized configurations (JavaScript enabled, DOM storage active, Cookie persistency, Hardware Acceleration, and custom Caching).
* **True Native UI Wrapper**: Complete elimination of browser UI. No address bars, visible URLs, toolbars, or default web navigation buttons.
* **Full-screen & Immersive Mode**: System UI customization to hide Android navigation/status bars where appropriate, offering a seamless native flow.

### 2.2 Biometric Authentication & Secure Session Management
* **Platform Biometrics**: Integration of Face ID, Touch ID, Android Fingerprint, and Face Unlock where supported.
* **Security Fallback**: Graceful fallback to Android PIN/Pattern/Password and iOS Passcode.
* **Biometric Toggle**: User-controlled setting to enable or disable biometric login.
* **Secure Token Vaulting**: Leveraging the OS-level secure storage (Keystore for Android, Keychain for iOS) to encrypt and unlock the web authenticated session securely, preventing plaintext password storage.

### 2.3 Comprehensive File & Download Management
* **Supported File Formats**: High-performance downloading, caching, and previewing of `PDF`, `PNG`, `JPG`, `ZIP`, `DOCX`, `XLSX`, and `PPTX`.
* **Download Manager**: Real-time progress indicators, progress bars, and localized file persistence using `path_provider`.
* **File Interaction**: Integration with `open_filex` allowing users to open downloaded files directly inside or outside the application.
* **In-App PDF Viewer**: Direct inline rendering of PDF files for a seamless native experience.

### 2.4 Secure Upload System
* **Media & Document Upload**: Multiple file selection, camera capture, and gallery image selection for upload fields inside the WebView.
* **File Compressor**: Optional background compression of image files before upload to optimize bandwidth.

### 2.5 Connectivity & Offline Resilience
* **Network Connectivity Monitor**: Real-time state listening using `connectivity_plus`.
* **Offline UI**: Elegant, user-friendly "No Internet Connection" overlay or full screen with retry mechanics.
* **PWA Capability**: Hybrid caching with WebView local cache, supporting Service Worker execution for offline PWA features.

---

## 3. Non-Functional Requirements

### 3.1 Security (MASVS Aligned)
* **Encryption**: AES-256 encryption for any local databases, configuration files, and credentials via platform-specific secure enclaves.
* **Network Security**: Strict HTTPS enforceability, disabling of cleartext HTTP traffic, and automated Safe Browsing checks.
* **Tamper Protection**: WebView debugging disabled in production releases.
* **SSL Error Prevention**: Robust verification and handling of SSL/TLS certificates with no fallback to insecure connections in production.

### 3.2 Performance & Scalability
* **Cold Start Time**: Launch to interactive screen in less than 2.0 seconds.
* **Frame Rate**: Consistent 60fps/120fps (ProMotion/High-Refresh) transitions.
* **Memory Management**: Automatic release of unused WebView resources, image caching thresholds, and selective garbage collection.
* **Executable Optimization**: Code shrinking (R8), resource shrinking, and Split-per-ABI compilation.

### 3.3 Reliability & Maintainability
* **Availability**: 99.9% uptime design on client-side logic.
* **Crash-free Rate**: Targeted >99% crash-free sessions.
* **Architecture**: Complete conformance to Clean Architecture and SOLID principles.

---

## 4. Complete Folder Structure

The project adopts a Clean Architecture folder structure organized by features or layers. Below is the comprehensive structure:

```
lib/
├── core/
│   ├── constants/
│   │   ├── app_colors.dart
│   │   ├── app_strings.dart
│   │   └── api_endpoints.dart
│   ├── errors/
│   │   ├── failure.dart
│   │   └── exceptions.dart
│   ├── security/
│   │   ├── biometrics_service.dart
│   │   └── secure_storage_service.dart
│   ├── services/
│   │   ├── connectivity_service.dart
│   │   ├── download_service.dart
│   │   ├── upload_service.dart
│   │   └── permission_service.dart
│   ├── theme/
│   │   ├── app_theme.dart
│   │   └── theme_provider.dart
│   └── utils/
│       ├── file_helper.dart
│       └── logger.dart
├── features/
│   ├── splash/
│   │   ├── presentation/
│   │   │   ├── screens/
│   │   │   │   └── splash_screen.dart
│   │   │   └── controllers/
│   │   │       └── splash_controller.dart
│   ├── auth/
│   │   ├── domain/
│   │   │   ├── repositories/
│   │   │   │   └── auth_repository.dart
│   │   │   └── usecases/
│   │   │       └── authenticate_biometrics.dart
│   │   ├── data/
│   │   │   ├── datasources/
│   │   │   │   └── secure_credentials_datasource.dart
│   │   │   └── repositories/
│   │   │       └── auth_repository_impl.dart
│   │   └── presentation/
│   │       ├── screens/
│   │       │   └── biometric_login_screen.dart
│   │       └── controllers/
│   │           └── auth_controller.dart
│   ├── wallet_webview/
│   │   ├── presentation/
│   │   │   ├── screens/
│   │   │   │   └── webview_screen.dart
│   │   │   ├── widgets/
│   │   │   │   ├── webview_error_overlay.dart
│   │   │   │   ├── webview_loader.dart
│   │   │   │   └── download_progress_bar.dart
│   │   │   └── controllers/
│   │   │       └── webview_controller.dart
│   └── offline/
│       └── presentation/
│           └── screens/
│               └── offline_screen.dart
└── main.dart
```

---

## 5. Architecture Diagram

```
+-------------------------------------------------------------------------+
|                              PRESENTATION                               |
|        (UI Screens, Custom Widgets, Controllers, Loading overlays)       |
+------------------------------------+------------------------------------+
                                     | Uses (State & Events)
                                     v
+-------------------------------------------------------------------------+
|                                 DOMAIN                                  |
|         (Core Business Logic, Use Cases, Repository Contracts)          |
+------------------------------------+------------------------------------+
                                     | Implemented by
                                     v
+-------------------------------------------------------------------------+
|                                  DATA                                   |
|   (Secure Storage, Biometrics APIs, Connectivity & Network, WebView)   |
+-------------------------------------------------------------------------+
                                     |
                                     v
+-------------------------------------------------------------------------+
|                           PLATFORM ABSTRACTIONS                         |
|   (iOS Keychain/FaceID, Android Keystore, local storage, InAppWebView)  |
+-------------------------------------------------------------------------+
```

---

## 6. Navigation Flow

```
                      +----------------------+
                      |      App Launch      |
                      +----------+-----------+
                                 |
                                 v
                      +----------------------+
                      |  Native Splash & JS  |
                      |    Initialization    |
                      +----------+-----------+
                                 |
                                 v
                      +----------------------+
                      |  Biometric Login     |
                      |   (If Enabled)       |
                      +----------+-----------+
                                 |
                     Success     v
                      +----------------------+
                      |  Main WebView Screen | <===================+
                      +----------+-----------+                     |
                                 |                                 |
               No Connection     | Connection Restored             |
                                 v                                 |
                      +----------------------+                     |
                      |   Offline Overlay    +---------------------+
                      |    & Retry State     |
                      +----------------------+
```

* **Back Navigation Policy**:
  * If the InAppWebView can navigate back in its history, pressing the system back button (or swipe gesture) goes back one page.
  * If no web history exists, a professional native Material 3 "Exit Application" confirmation dialog is displayed.

---

## 7. State Management Design

### 7.1 Selection & Justification: Riverpod
After meticulous comparison, **Riverpod** is selected as the state management and dependency injection solution for the following reasons:
1. **Compile-Time Safety**: No risk of encountering runtime `ProviderNotFoundException`.
2. **No BuildContext Dependency**: Allows state management and API triggers to be cleanly decoupled from the UI layer.
3. **Uni-directional Data Flow**: Guarantees predictable state transitions, making the integration of asynchronous events (like network dropouts or biometric prompts) clean and testable.
4. **Mockability**: Simplifies writing comprehensive Unit, Widget, and Integration tests.

### 7.2 Implementation Flow
* `StateNotifier` and `StateNotifierProvider` (or the modern `@riverpod` syntax) will represent UI-specific state objects (e.g., `WebViewState`, `ConnectionState`, `BiometricState`).
* Ref-based consumption will inject repositories and background services directly.

---

## 8. Dependency Injection Strategy

Riverpod will serve as the core Dependency Injection (DI) engine. We will define global providers for our primary singletons and services:

```dart
final secureStorageProvider = Provider<SecureStorageService>((ref) => SecureStorageServiceImpl());
final biometricServiceProvider = Provider<BiometricsService>((ref) => BiometricsServiceImpl(ref.watch(secureStorageProvider)));
final connectivityServiceProvider = Provider<ConnectivityService>((ref) => ConnectivityServiceImpl());
final permissionServiceProvider = Provider<PermissionService>((ref) => PermissionServiceImpl());
final downloadServiceProvider = Provider<DownloadService>((ref) => DownloadServiceImpl());
```

This avoids manual constructor injection chains, makes dependencies transparent, and allows seamless mock injection during unit testing:

```dart
final container = ProviderContainer(
  overrides: [
    connectivityServiceProvider.overrideWithValue(MockConnectivityService()),
  ],
);
```

---

## 9. Security Architecture

Our security structure aligns rigorously with **MASVS (v2.0)**:

| Category | Security Control Implementation |
| :--- | :--- |
| **Data Storage** | Cryptographic token storage using hardware-backed Android Keystore and iOS Keychain via `flutter_secure_storage`. Zero storage of plain text user passwords. |
| **Cryptography** | Standard cryptographic algorithms (AES-GCM 256-bit, SHA-256) inside platform-native secure storage enclaves. |
| **Authentication** | Biometric credential binding. Disallow PIN bypass unless secure fallback is processed by the OS. Session synchronization with server cookies. |
| **Network Comm.** | Strict TLS configuration. Enforced HTTPS only. SSL handshake verification. Debug modes block self-signed certificates in production. |
| **Platform Integ.** | Deep validation of intents, permissions handler, isolation of web contexts, and strict origin white-listing. |
| **App Resilience** | Disabling of WebView developer tools and inspectable features in Release builds. Safe-guarding app screen preview inside background tasks (App Obfuscation/Shielding). |

---

## 10. Platform Permission Matrix

To respect user privacy, permissions are requested **on-demand** (just-in-time) only when a feature is activated by the user inside the WebView.

| Platform Permission | Key Feature Supported | Requesting Mechanism |
| :--- | :--- | :--- |
| `Permission.camera` | Document upload, selfie verification | permission_handler |
| `Permission.microphone` | Voice verification or chat features | permission_handler |
| `Permission.location` | Location validation during transactions | permission_handler |
| `Permission.photos` / `Permission.storage` | Access files/photos for upload, downloads | permission_handler |
| `Permission.reminders` / `Notifications` | Transaction alerts, notifications (Android 13+) | permission_handler |

---

## 11. Build Configuration

### 11.1 Android (`android/app/build.gradle`)
* **Min SDK**: `23` (Android 6.0) to ensure complete support for Biometrics and WebViews.
* **Target SDK**: `34` (Android 14).
* **Release Settings**:
  * `minifyEnabled true`
  * `shrinkResources true`
  * `ndk { abiFilters "armeabi-v7a", "arm64-v8a", "x86_64" }` (Split-per-ABI ready)

### 11.2 iOS (`ios/Runner/Info.plist`)
* **Minimum Deployment Target**: `13.0` (Supports modern FaceID APIs and WebKit caching).
* **Privacy Keys (Info.plist)**:
  * `NSCameraUsageDescription`
  * `NSMicrophoneUsageDescription`
  * `NSLocationWhenInUseUsageDescription`
  * `NSPhotoLibraryUsageDescription`
  * `NSFaceIDUsageDescription`

### 11.3 macOS (`macos/Runner/Configs/AppInfo.xcconfig`)
* **Minimum Deployment Target**: `10.15` (Catalina) to enable security features and WebView support.
* **Sandbox Entitlements**: Enable client network access, hardware access for camera/microphone, and downloads.

---

## 12. Error Handling Strategy

The system handles failures gracefully to avoid negative user experiences:

* **No Connection / Timeout**: Captured globally by the connectivity stream and `onReceivedError` or `onReceivedHttpError` in the WebView. An custom interactive overlay screen displays immediately with a "Retry" trigger.
* **404 / 500 / SSL Errors**: Custom web-resource loading fallback. If the WebView responds with an error status code, it redirects or displays an internal elegant Material 3 error widget, preventing the raw browser error page from appearing.
* **Permission Denied**: Explanatory snackbars or overlay descriptions that prompt users to enable the setting in System Settings if they previously denied it.
* **Biometric Failures**: Clear notifications with immediate fallback to device PIN/passcode.

---

## 13. Offline Strategy

1. **Active Real-Time Monitoring**: Real-time listening to network changes using `connectivity_plus`.
2. **Intelligent WebView Caching**: Configuring `InAppWebViewSettings` with `cacheMode: CacheMode.LOAD_DEFAULT` (or fallback to `LOAD_CACHE_ELSE_NETWORK`).
3. **PWA Service Worker Support**: Enabling Service Worker capabilities to allow fully persistent offline storage, allowing immediate load times.
4. **Graceful Re-sync**: Upon network reconnection, automatically reload the current URL state, restoring the user session smoothly.

---

## 14. Caching Strategy

* **InAppWebView Caching**: Enabling of HTTP cache, application cache, and web database storage.
* **Cookie Management**: Using `CookieManager` to ensure persistent storage of session tokens across app restarts.
* **Image / Asset Cache**: Flutter-native assets (Splash assets, icons) are fully loaded locally to speed up startup times.

---

## 15. Testing Strategy

We follow a strict Test Pyramid strategy:

* **Unit Tests**: Coverage of secure storage encryption wrapper, biometric integration business logic, permission verification logic, and controller state machines.
* **Widget Tests**: Testing of custom loading screens, No-Internet error interfaces, permission prompt popups, and dialog overlays.
* **Integration Tests**: Comprehensive test suite executing end-to-end tests inside target environments, validating WebView lifecycle, secure token verification, and connectivity transition reactions.
* **Mock Objects**: Utilizing mock libraries to mimic camera, biometrics, and internet hardware responses.

---

## 16. Deployment Strategy

* **Android Distribution**: Play Store deployment via App Bundle (AAB).
* **iOS Distribution**: App Store deployment via TestFlight testing channels.
* **macOS Distribution**: macOS App Store distribution with sandboxing fully configured.

---

## 17. CI/CD Strategy

* **Automated Pipeline**: Utilizing GitHub Actions to continuously build and verify the code on every Pull Request.
* **Phases**:
  1. **Linter & Analyzer**: Execute `flutter analyze` and `dart format` checks to enforce strict clean-code rules.
  2. **Test Runner**: Run all Unit and Widget tests.
  3. **Build Compilation**: Package-building automation for iOS and Android configurations using secure build keys.
  4. **Artifact Management**: Storage of compiled APK/AAB and IPA builds as testable releases.

---

### *Approved and Awaiting Phase 2 Initialization...*
