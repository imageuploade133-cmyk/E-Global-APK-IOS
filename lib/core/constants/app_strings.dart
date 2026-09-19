class AppStrings {
  static const String appName = 'E-Global Pay';
  static const String baseUrl = 'https://e-global-197077.vercel.app/';
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
    if (uri.scheme.toLowerCase() != 'https') return false;
    final expectedUri = Uri.parse(baseUrl);
    final host = uri.host.toLowerCase();
    final expectedHost = expectedUri.host.toLowerCase();
    return host == expectedHost || host.endsWith('.$expectedHost');
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
  static const String offlineTitle = 'Unable to connect';
  static const String offlineMessage = 'Please check your internet connection and try again.';
}
