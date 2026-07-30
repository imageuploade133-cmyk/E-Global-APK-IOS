import 'package:flutter_riverpod/flutter_riverpod.dart';

class WebViewState {
  final double progress;
  final bool isLoading;
  final bool hasError;
  final String errorMessage;

  const WebViewState({this.progress = 0.0, this.isLoading = true, this.hasError = false, this.errorMessage = ''});

  WebViewState copyWith({double? progress, bool? isLoading, bool? hasError, String? errorMessage}) {
    return WebViewState(
      progress: progress ?? this.progress,
      isLoading: isLoading ?? this.isLoading,
      hasError: hasError ?? this.hasError,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class WebViewNotifier extends StateNotifier<WebViewState> {
  WebViewNotifier() : super(const WebViewState());

  void setProgress(double progress) {
    state = state.copyWith(progress: progress);
  }

  void setLoading(bool isLoading) {
    state = state.copyWith(isLoading: isLoading);
  }

  void setError(bool hasError, [String message = '']) {
    state = state.copyWith(hasError: hasError, errorMessage: message);
  }
}

final webViewProvider = StateNotifierProvider<WebViewNotifier, WebViewState>((ref) {
  return WebViewNotifier();
});
