import 'dart:io';

import 'package:PiliPlus/plugin/pl_player/models/play_status.dart';
import 'package:PiliPlus/services/audio_handler.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('audio_handler_test');
    Hive.init(tempDir.path);
    GStorage.setting = await Hive.openBox('setting');
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test('publishes playing state before media metadata arrives', () {
    final handler = VideoPlayerServiceHandler()
      ..enableBackgroundPlay = true
      ..onStatusChange(PlayerStatus.playing, false);
    final state = handler.playbackState.value;

    expect(state.playing, isTrue);
    expect(state.processingState, AudioProcessingState.ready);
    expect(
      state.controls.map((control) => control.action),
      contains(MediaAction.pause),
    );
  });
}
