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

  /// Returns what the platform reports back (the audio session's state),
  /// `null` when nothing was sent or reported.
  static Future<Object?> update(Object owner, Map<String, Object> state) async {
    if (identical(_owner, owner)) {
      return channel.invokeMethod<Object?>('NowPlaying.Update', state);
    }
    return null;
  }

  static Future<void> release(Object owner) async {
    if (!identical(_owner, owner)) return;
    _owner = null;
    channel.setMethodCallHandler(null);
    await channel.invokeMethod('NowPlaying.Clear');
  }
}
