import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String? keyFor({
    bool tempPlayerConf = false,
    required bool isWiFi,
    bool auto = false,
  }) => PlPlayerController.videoQaKeyFor(
    tempPlayerConf: tempPlayerConf,
    isWiFi: isWiFi,
    auto: auto,
  );

  test('a pick in the player becomes the default for its network', () {
    expect(keyFor(isWiFi: true), SettingBoxKey.defaultVideoQa);
    expect(keyFor(isWiFi: false), SettingBoxKey.defaultVideoQaCellular);
  });

  test('on Wi-Fi with 自动 a pick leaves 自动 in place', () {
    expect(keyFor(isWiFi: true, auto: true), isNull);
    // Cellular has no 自动 of its own
    expect(
      keyFor(isWiFi: false, auto: true),
      SettingBoxKey.defaultVideoQaCellular,
    );
  });

  test('with player settings for the current video only, nothing is saved', () {
    expect(keyFor(tempPlayerConf: true, isWiFi: true), isNull);
    expect(keyFor(tempPlayerConf: true, isWiFi: false), isNull);
  });
}
