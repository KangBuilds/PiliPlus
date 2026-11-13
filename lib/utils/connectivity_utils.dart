import 'dart:async' show StreamSubscription;

import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

abstract final class ConnectivityUtils {
  /// The last answer, kept current by [_changes]: opening a video asks
  /// several times, and each check is a round trip to the platform.
  static bool? _wifi;
  // Listens for as long as the app runs
  // ignore: cancel_subscriptions
  static StreamSubscription<List<ConnectivityResult>>? _changes;

  static Future<bool> get isWiFi async {
    if (!PlatformUtils.isMobile) return false;
    if (_wifi case final wifi?) return wifi;
    try {
      _changes ??= Connectivity().onConnectivityChanged.listen(
        (results) => _wifi = results.contains(ConnectivityResult.wifi),
        // Unknown again: the next call checks
        onError: (_) => _wifi = null,
      );
      return _wifi = (await Connectivity().checkConnectivity()).contains(
        ConnectivityResult.wifi,
      );
    } catch (_) {
      return true;
    }
  }
}
