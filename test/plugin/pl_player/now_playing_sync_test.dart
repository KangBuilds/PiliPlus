import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  bool needsSync({
    required int position,
    int syncedPosition = 100,
    required int elapsedMs,
    double rate = 1,
    bool playing = true,
  }) => PlPlayerController.nowPlayingNeedsSync(
    position: position,
    syncedPosition: syncedPosition,
    elapsedMs: elapsedMs,
    rate: rate,
    playing: playing,
  );

  test('playback running on needs nothing: the system counts by itself', () {
    expect(needsSync(position: 101, elapsedMs: 1000), isFalse);
    expect(needsSync(position: 105, elapsedMs: 5000), isFalse);
    // At double speed the clock runs twice as fast as well
    expect(needsSync(position: 110, elapsedMs: 5000, rate: 2), isFalse);
  });

  test('a seek sets the clock again', () {
    expect(needsSync(position: 300, elapsedMs: 1000), isTrue);
    expect(needsSync(position: 20, elapsedMs: 1000), isTrue);
  });

  test('a stall the clock ran through sets it again', () {
    expect(needsSync(position: 101, elapsedMs: 4000), isTrue);
  });

  test('paused, the clock stands still', () {
    expect(needsSync(position: 100, elapsedMs: 5000, playing: false), isFalse);
    expect(needsSync(position: 103, elapsedMs: 5000, playing: false), isTrue);
  });

  test('it is set now and then anyway', () {
    expect(needsSync(position: 110, elapsedMs: 10000), isTrue);
  });
}
