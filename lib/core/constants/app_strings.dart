class AppStrings {
  AppStrings._();

  static const appName = 'E-Global Wallet';

  // Secure storage keys
  static const savedEmailKey = 'remembered_user_email';

  // Offline screen
  static const noInternetTitle = 'No Internet Connection';
  static const noInternetSubtitle =
      'Please check your connection and try again.';
  static const retryLabel = 'Retry';
  static const cancelLabel = 'Cancel';

  // WebView error
  static const webViewLoadErrorTitle = 'Something went wrong';
  static const webViewLoadErrorSubtitle =
      'We couldn\'t load the page. Please check your connection.';
  static const webViewCrashTitle = 'App Error';
  static const webViewCrashSubtitle =
      'The page failed to load. Please try again.';
  static const tryAgainLabel = 'Try Again';

  // General
  static const loading = 'Loading...';
  static const error = 'Error';
  static const ok = 'OK';

  /// Validates whether a URL origin is a trusted wallet origin.
  static bool isTrustedWalletOrigin(Uri uri) {
    return uri.scheme == 'https' &&
        uri.host == 'e-global-197077.vercel.app';
  }
}
