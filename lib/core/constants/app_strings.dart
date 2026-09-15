class AppStrings {
  AppStrings._();

  static constString appName = 'E-Global Wallet';

  // Secure storage keys
  static constString savedEmailKey = 'remembered_user_email';

  // Offline screen
  static constString noInternetTitle = 'No Internet Connection';
  static constString noInternetSubtitle =
      'Please check your connection and try again.';
  static constString retryLabel = 'Retry';
  static constString cancelLabel = 'Cancel';

  // WebView error
  static constString webViewLoadErrorTitle = 'Something went wrong';
  static constString webViewLoadErrorSubtitle =
      'We couldn\'t load the page. Please check your connection.';
  static constString webViewCrashTitle = 'App Error';
  static constString webViewCrashSubtitle =
      'The page failed to load. Please try again.';
  static constString tryAgainLabel = 'Try Again';

  // General
  static constString loading = 'Loading...';
  static constString error = 'Error';
  static constString ok = 'OK';

  /// Validates whether a URL origin is a trusted wallet origin.
  static bool isTrustedWalletOrigin(Uri uri) {
    return uri.scheme == 'https' &&
        uri.host == 'e-global-197077.vercel.app';
  }
}
