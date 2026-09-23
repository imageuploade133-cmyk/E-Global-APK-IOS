class AppStrings {
  static const String appName = 'E-Global Pay';
  static const String baseUrl = 'https://e-global-197077.vercel.app/';
  static const String bundleVersion = '1.0.0';
  static const String localHostBaseUrl = 'http://localhost:8080/';
  static const String packageIdentifier = 'com.eglobal.wallet';
  static const String biometricKey = 'biometric_enabled';
  static const String credentialsKey = 'secure_wallet_credentials';
  static const String savedEmailKey = 'remembered_user_email';

  static const List<String> trustedExternalGateways = [
    'paystack.com',
    'flutterwave.com',
    'interswitchng.com',
    'monnify.com',
    'stripe.com',
    'verify.identitypass.ai',
    'smileidentity.com',
  ];

  static bool isTrustedWalletOrigin(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    final host = uri.host.toLowerCase();

    // 1. Local web asset server origin (exact host check)
    if (scheme == 'http') {
      return host == 'localhost' || host == '127.0.0.1';
    }

    // 2. Production Vercel web origin (exact host/subdomain check)
    if (scheme == 'https') {
      final expectedUri = Uri.parse(baseUrl);
      final expectedHost = expectedUri.host.toLowerCase();
      return host == expectedHost || host == 'e-global-197077.vercel.app' || host.endsWith('.$expectedHost');
    }

    return false;
  }

  static bool isTrustedGatewayOrigin(Uri uri) {
    if (uri.scheme.toLowerCase() != 'https') return false;
    final host = uri.host.toLowerCase();
    return trustedExternalGateways.any(
      (gw) => host == gw || host.endsWith('.$gw'),
    );
  }

  // UI Strings
  static const String loading = 'Loading...';
  static const String tryAgainLabel = 'Try Again';
  static const String retry = 'Retry';
  static const String webViewCrashTitle = 'Unable to connect';
  static const String webViewCrashSubtitle = 'Please check your internet connection and try again.';
  static const String webViewLoadErrorTitle = 'Unable to connect';
  static const String webViewLoadErrorSubtitle = 'Please check your internet connection and try again.';
  static const String offlineTitle = 'Connection Lost';
  static const String offlineMessage = 'We couldn\'t connect to the server. Please check your internet connection.';
}
