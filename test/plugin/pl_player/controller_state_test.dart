import 'dart:async';

import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_status.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show EdgeInsets;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:native_device_orientation/native_device_orientation.dart';

class _SettingsBox implements Box<dynamic> {
  final stored = <dynamic, dynamic>{};

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      stored[key] ?? (key == 'buvid' ? 'test-buvid' : defaultValue);

  @override
  Future<void> putAll(Map<dynamic, dynamic> entries) async =>
      stored.addAll(entries);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Orientation extends NativeDeviceOrientationPlatform {
  final events = StreamController<OrientationParams>.broadcast(sync: true);

  @override
  Stream<OrientationParams> onOrientationChanged({
    int? angleDegrees,
    bool checkIsAutoRotate = true,
  }) => events.stream;

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late NativeDeviceOrientationPlatform originalOrientation;
  late _Orientation orientation;
  late PlPlayerController player;
  final settings = _SettingsBox();
  final orientationChanges = <MethodCall>[];

  setUpAll(() {
    GStorage.setting = settings;
    GStorage.video = _SettingsBox();
    GStorage.localCache = _SettingsBox();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      ..setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'SystemChrome.setPreferredOrientations') {
          orientationChanges.add(call);
        }
        return null;
      })
      ..setMockMethodCallHandler(
        const MethodChannel('com.PiliPlus/now_playing'),
        (_) async => null,
      );
  });

  setUp(() {
    settings.stored.clear();
    originalOrientation = NativeDeviceOrientationPlatform.instance;
    NativeDeviceOrientationPlatform.instance = orientation = _Orientation();
    player = PlPlayerController.getInstance();
    orientationChanges.clear();
  });

  tearDown(() async {
    player.playerStatus.value = PlayerStatus.paused;
    player.dispose();
    await orientation.events.close();
    NativeDeviceOrientationPlatform.instance = originalOrientation;
  });

  test('locked controls ignore all sensor-driven orientation changes', () {
    player.isFullScreen.value = true;
    player.controlsLock.value = true;
    for (final value in DeviceOrientation.values) {
      orientation.events.add((orientation: value, isAutoRotate: true));
    }
    expect(orientationChanges, isEmpty);
    expect(player.isFullScreen.value, isTrue);
  });

  test('unlocked controls still handle orientation changes', () {
    player.isFullScreen.value = true;
    orientation.events.add((
      orientation: DeviceOrientation.landscapeRight,
      isAutoRotate: true,
    ));
    expect(orientationChanges.single.arguments, [
      'DeviceOrientation.landscapeRight',
    ]);
  });

  test('background player ignores orientation changes', () {
    player.visible = false;
    orientation.events.add((
      orientation: DeviceOrientation.landscapeLeft,
      isAutoRotate: true,
    ));
    expect(orientationChanges, isEmpty);
  });

  test('subtitle avoidance restores the original padding exactly once', () {
    player
      ..subtitlePaddingB = 24
      ..adjustSubtitlePadding()
      ..adjustSubtitlePadding();
    expect(player.subtitlePaddingB, 70);
    expect(player.subtitleConfig.value.padding.bottom, 70);
    player.resetSubtitlePadding();
    expect(player.subtitlePaddingB, 24);
    expect(player.subtitleConfig.value.padding.bottom, 24);
    expect(player.tmpSubtitlePaddingB, isNull);
    player.resetSubtitlePadding();
    expect(player.subtitlePaddingB, 24);
  });

  test('manual subtitle setting is not overwritten when controls hide', () {
    player
      ..subtitlePaddingB = 24
      ..adjustSubtitlePadding()
      ..updateSubtitleBottomPadding(42)
      ..resetSubtitlePadding();
    expect(player.subtitlePaddingB, 42);
    expect(player.subtitleConfig.value.padding.bottom, 42);
    expect(player.tmpSubtitlePaddingB, isNull);
  });

  test(
    'dragging subtitles clears avoidance, updates style and persists padding',
    () {
      player
        ..subtitlePaddingB = 24
        ..adjustSubtitlePadding()
        ..onUpdatePadding(const EdgeInsets.only(bottom: 500))
        ..resetSubtitlePadding();
      expect(player.subtitlePaddingB, 200);
      expect(player.subtitleConfig.value.padding.bottom, 200);
      expect(settings.stored[SettingBoxKey.subtitlePaddingB], 200);
    },
  );

  test('temporary control avoidance is never persisted as user padding', () {
    player
      ..subtitlePaddingB = 24
      ..adjustSubtitlePadding()
      ..putSubtitleSettings();
    expect(settings.stored[SettingBoxKey.subtitlePaddingB], 24);
    expect(player.subtitlePaddingB, 70);
  });

  test('already elevated subtitles do not need temporary avoidance', () {
    player
      ..subtitlePaddingB = 100
      ..adjustSubtitlePadding();
    expect(player.tmpSubtitlePaddingB, isNull);
    player.resetSubtitlePadding();
    expect(player.subtitlePaddingB, 100);
  });
}
