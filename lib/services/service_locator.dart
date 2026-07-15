import 'package:PiliPlus/services/audio_handler.dart';
import 'package:PiliPlus/services/audio_session.dart';

VideoPlayerServiceHandler? videoPlayerServiceHandler;
AudioSessionHandler? audioSessionHandler;

final Future<VideoPlayerServiceHandler> _setupFuture = _setupServiceLocator();

Future<VideoPlayerServiceHandler> setupServiceLocator() => _setupFuture;

void withAudioService(void Function(VideoPlayerServiceHandler) action) {
  setupServiceLocator().then(action).ignore();
}

Future<VideoPlayerServiceHandler> _setupServiceLocator() async {
  final session = AudioSessionHandler();
  final (audio, _) = await (initAudioService(), session.initSession()).wait;
  videoPlayerServiceHandler = audio;
  audioSessionHandler = session;
  return audio;
}
