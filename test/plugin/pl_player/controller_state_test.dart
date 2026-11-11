import 'dart:async';

import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_status.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:native_device_orientation/native_device_orientation.dart';

class _SettingsBox implements Box<dynamic> {
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      key == 'buvid' ? 'test-buvid' : defaultValue;

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
  final orientationChanges = <MethodCall>[];

  setUpAll(() {
    GStorage.setting = _SettingsBox();
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
}
