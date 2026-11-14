import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_status.dart';
import 'package:audio_session/audio_session.dart';

class AudioSessionHandler {
  late AudioSession session;
  bool _playInterrupted = false;

  /// mpv options that leave `AVAudioSession` to the app.
  ///
  /// mpv's AudioUnit output otherwise sets the category, mode and options
  /// itself and deactivates the session whenever its audio stops, competing
  /// with this handler and the Now Playing code in AppDelegate. Every [Player]
  /// is created with these options.
  static const mpvOptions = {'audiounit-skip-session-management': 'yes'};

  Future<bool> setActive(bool active) {
    return session.setActive(active);
  }

  /// Gives the session up once a player is gone, telling other apps they may
  /// resume their audio, as mpv did when its audio output closed. (A pause
  /// deactivates without telling them.) iOS refuses while another player
  /// still plays, which is what should happen, so the failure is ignored.
  Future<void> deactivate() async {
    try {
      await session.setActive(
        false,
        avAudioSessionSetActiveOptions:
            AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
      );
    } catch (_) {}
  }

  Future<void> initSession() async {
    session = await AudioSession.instance;
    // What mpv used to set: playback in movie mode.
    await session.configure(
      const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionMode: AVAudioSessionMode.moviePlayback,
      ),
    );

    session.interruptionEventStream.listen((event) {
      final playerStatus = PlPlayerController.getPlayerStatusIfExists();
      // final player = PlPlayerController.getInstance();
      if (event.begin) {
        if (playerStatus != PlayerStatus.playing) return;
        // if (!player.playerStatus.playing) return;
        switch (event.type) {
          case AudioInterruptionType.duck:
            PlPlayerController.setVolumeIfExists(
              (PlPlayerController.getVolumeIfExists() ?? 0) * 0.5,
              showIndicator: false,
            );
            // player.setVolume(player.volume.value * 0.5);
            break;
          case AudioInterruptionType.pause:
            PlPlayerController.pauseIfExists(isInterrupt: true);
            // player.pause(isInterrupt: true);
            _playInterrupted = true;
            break;
          case AudioInterruptionType.unknown:
            PlPlayerController.pauseIfExists(isInterrupt: true);
            // player.pause(isInterrupt: true);
            _playInterrupted = true;
            break;
        }
      } else {
        switch (event.type) {
          case AudioInterruptionType.duck:
            PlPlayerController.setVolumeIfExists(
              (PlPlayerController.getVolumeIfExists() ?? 0) * 2,
              showIndicator: false,
            );
            // player.setVolume(player.volume.value * 2);
            break;
          case AudioInterruptionType.pause:
            if (_playInterrupted) PlPlayerController.playIfExists();
            //player.play();
            break;
          case AudioInterruptionType.unknown:
            break;
        }
        _playInterrupted = false;
      }
    });

    // 耳机拔出暂停
    session.becomingNoisyEventStream.listen((_) {
      PlPlayerController.pauseIfExists();
      // final player = PlPlayerController.getInstance();
      // if (player.playerStatus.playing) {
      //   player.pause();
      // }
    });
  }
}
