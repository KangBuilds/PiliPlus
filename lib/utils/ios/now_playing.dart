import 'package:flutter/services.dart';

abstract final class NativeNowPlaying {
  static const channel = MethodChannel('com.PiliPlus/now_playing');
  static Object? _owner;

  static void claim(Object owner, Future<void> Function(MethodCall) handler) {
    _owner = owner;
    channel.setMethodCallHandler(handler);
  }

  /// Whether [owner]'s updates reach the system.
  static bool isOwner(Object owner) => identical(_owner, owner);

  static Future<void> update(Object owner, Map<String, Object> state) async {
    if (identical(_owner, owner)) {
      await channel.invokeMethod('NowPlaying.Update', state);
    }
  }

  static Future<void> release(Object owner) async {
    if (!identical(_owner, owner)) return;
    _owner = null;
    channel.setMethodCallHandler(null);
    await channel.invokeMethod('NowPlaying.Clear');
  }
}
