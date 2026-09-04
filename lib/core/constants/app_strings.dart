class AppStrings {
  static const String appName = 'E-Global Wallet';
  static const String baseUrl = 'https://e-global-197077.vercel.app/';
  static const String packageIdentifier = 'com.eglobal.wallet';
  static const String biometricKey = 'biometric_enabled';
  static const String credentialsKey = 'secure_wallet_credentials';

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
}
