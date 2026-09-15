import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../errors/failure.dart';
import '../utils/logger.dart';

/// Provides the current connectivity state as a stream.
final connectivityProvider = StreamProvider<bool>((ref) {
  return Connectivity()
      .onConnectivityChanged
      .map((List<ConnectivityResult> result) {
        final hasConnection =
            result.isNotEmpty &&
            !result.contains(ConnectivityResult.none);
        AppLogger.debug(
          'Connectivity changed: ${result.join(", ")} → $hasConnection',
          tag: 'Connectivity',
        );
        return hasConnection;
      })
      .handleError((Object e) {
        AppLogger.error('Connectivity stream error', tag: 'Connectivity', error: e);
        return false;
      });
});

/// Synchronous check of current connectivity.
class ConnectivityService {
  ConnectivityService._();

  static Future<bool> hasConnection() async {
    final result = await Connectivity().checkConnectivity();
    final connected = result.isNotEmpty && !result.contains(ConnectivityResult.none);
    AppLogger.debug('Synchronous connectivity check: $connected', tag: 'Connectivity');
    return connected;
  }

  /// Throws [NetworkFailure] if no connection; returns true otherwise.
  static Future<void> requireConnection() async {
    final connected = await hasConnection();
    if (!connected) {
      throw const NetworkFailure();
    }
  }
}

/// Implementation used by [connectivityServiceProvider] in core_providers.dart.
/// Delegates to [ConnectivityService] static methods.
class ConnectivityServiceImpl implements ConnectivityService {
  ConnectivityServiceImpl();

  @override
  Future<bool> hasConnection() => ConnectivityService.hasConnection();

  @override
  Future<void> requireConnection() => ConnectivityService.requireConnection();
}
