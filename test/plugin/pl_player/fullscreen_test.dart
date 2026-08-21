import 'package:PiliPlus/plugin/pl_player/utils/fullscreen.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('forced orientation bypasses the cached value', () async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'SystemChrome.setPreferredOrientations') calls++;
          return null;
        });

    await landscapeRightMode(force: true);
    await landscapeRightMode(force: true);

    expect(calls, 2);
  });
}
