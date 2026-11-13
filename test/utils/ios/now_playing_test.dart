import 'package:PiliPlus/utils/ios/now_playing.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'native session failures reach the caller and allow later updates',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final owner = Object();
      NativeNowPlaying.claim(owner, (_) async {});
      addTearDown(() async {
        messenger.setMockMethodCallHandler(
          NativeNowPlaying.channel,
          (_) async => null,
        );
        await NativeNowPlaying.release(owner);
        messenger.setMockMethodCallHandler(NativeNowPlaying.channel, null);
      });
      messenger.setMockMethodCallHandler(NativeNowPlaying.channel, (_) async {
        throw PlatformException(
          code: 'audio_session_error',
          message: 'Activation failed',
          details: {'domain': 'NSOSStatusErrorDomain', 'code': 1},
        );
      });

      await expectLater(
        NativeNowPlaying.update(owner, {'active': true, 'playing': true}),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'audio_session_error',
          ),
        ),
      );

      var updates = 0;
      messenger.setMockMethodCallHandler(NativeNowPlaying.channel, (
        call,
      ) async {
        if (call.method == 'NowPlaying.Update') updates++;
        return null;
      });
      await NativeNowPlaying.update(owner, {'active': true, 'playing': true});
      expect(updates, 1);
    },
  );

  test(
    'previous player cannot update or clear the current media session',
    () async {
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(NativeNowPlaying.channel, (
        call,
      ) async {
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
    },
  );
}
