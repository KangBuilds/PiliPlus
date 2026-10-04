import 'package:PiliPlus/utils/ios/now_playing.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('previous player cannot update or clear the current media session', () async {
    final calls = <MethodCall>[];
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(NativeNowPlaying.channel, (call) async {
      calls.add(call);
      return null;
    });
    final video = Object();
    final audio = Object();
    NativeNowPlaying.claim(video, (_) async {});
    NativeNowPlaying.claim(audio, (_) async {});
    await NativeNowPlaying.update(video, {'title': 'old video'});
    await NativeNowPlaying.release(video);
    await NativeNowPlaying.update(audio, {'title': 'current audio'});
    expect(calls.single.method, 'NowPlaying.Update');
    expect(calls.single.arguments['title'], 'current audio');
    await NativeNowPlaying.release(audio);
    expect(calls.last.method, 'NowPlaying.Clear');
    messenger.setMockMethodCallHandler(NativeNowPlaying.channel, null);
  });
}
