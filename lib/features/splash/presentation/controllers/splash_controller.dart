import 'package:flutter_riverpod/flutter_riverpod.dart';

enum SplashStatus { initial, loading, authenticated, unauthenticated, offline }

class SplashState {
  final SplashStatus status;
  const SplashState(this.status);
}

class SplashNotifier extends StateNotifier<SplashState> {
  SplashNotifier() : super(const SplashState(SplashStatus.initial));

  void setStatus(SplashStatus status) {
    state = SplashState(status);
  }
}

final splashProvider = StateNotifierProvider<SplashNotifier, SplashState>((ref) {
  return SplashNotifier();
});
