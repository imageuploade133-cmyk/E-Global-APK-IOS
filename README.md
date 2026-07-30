# E-Global Wallet Mobile Application

A production-grade, highly secure, and offline-resilient hybrid Flutter mobile application for **E-Global Wallet**. Powered by Flutter, Riverpod, and modern system enclaves, it supports Android (mobiles & tablets), iOS (iPhones & iPads), and macOS with deep native feature integration.

## Key Features

- **Immersive Material 3 Wrapper**: Complete removal of browser chrome/bars for a modern, native look and feel.
- **Biometric Security**: Built-in biometric login (Face ID, Touch ID, Fingerprint, Face Unlock) with secure session storage using device enclaves (Keychain & Keystore).
- **Offline Resilience & Caching**: Smart connectivity listeners (`connectivity_plus`) with automated PWA Service Worker caching and beautiful fallback offline screens.
- **Advanced File Management**: On-demand download and uploads support (PDF, ZIP, DOCX, XLSX, images) with live UI progress tracking and inline file execution (`open_filex`).
- **Dynamic JIT Permission Handling**: Requests system capabilities (Camera, Mic, Location) only when requested by web components.

---

## Technical Specifications

Detailed architecture diagrams, security matrices, and deployment configurations are documented in:
👉 **[docs/SPECIFICATIONS.md](docs/SPECIFICATIONS.md)**

---

## Folder Architecture

```
lib/
├── core/
│   ├── constants/       # App-wide colors, strings, API routes
│   ├── errors/          # Custom exceptions and failures
│   ├── security/        # Secure storage and biometrics implementations
│   ├── services/        # Connectivity, JIT permissions and DI providers
│   ├── theme/           # Light & Dark Material 3 themes
│   └── utils/           # Shared helpers and loggers
└── features/
    ├── splash/          # Custom fade-in native launch splash
    ├── auth/            # Biometric validation overlays
    ├── offline/         # Network loss overlays & reload buttons
    └── wallet_webview/  # Core InAppWebView setup & files handlers
```

---

## Getting Started

### Prerequisites
- **Flutter SDK**: `^3.11.0` or higher
- **Dart SDK**: `^3.11.0` or higher
- **Xcode** (for iOS/macOS compilation)
- **Android Studio & Gradle** (for Android compilation)

### Installation
1. Clone the repository.
2. Install all required dependencies:
   ```bash
   flutter pub get
   ```
3. Run code formatting:
   ```bash
   dart format -l 120 lib/
   ```

### Running the Application
- Run in Debug mode on your connected simulator/device:
  ```bash
  flutter run
  ```

### Build Guides

#### Android Build (AAB & APK)
Generate split-per-ABI optimized release builds:
```bash
flutter build appbundle --release
flutter build apk --release --split-per-abi
```

#### iOS Build
Package the app inside an archive and prepare for TestFlight upload:
```bash
flutter build ipa --release
```

#### macOS Build
Compile the sandboxed macOS desktop client:
```bash
flutter build macos --release
```

---

## Quality & Testing
Run the complete widget and unit test suite:
```bash
flutter test
```
To run linter validations:
```bash
flutter analyze
```

---

## License
Confidential & Proprietary – E-Global Wallet, All Rights Reserved.
