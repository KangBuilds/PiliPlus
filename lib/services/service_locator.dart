import 'package:PiliPlus/services/audio_session.dart';

AudioSessionHandler? audioSessionHandler;

final Future<void> _setupFuture = _setupAudioSession();

Future<void> setupAudioSession() => _setupFuture;

Future<void> _setupAudioSession() async {
  final session = AudioSessionHandler();
  await session.initSession();
  audioSessionHandler = session;
}
