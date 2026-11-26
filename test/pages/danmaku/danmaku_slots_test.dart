import 'package:PiliPlus/pages/danmaku/view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('adds only the first slot when nothing was added yet', () {
    expect(danmakuSlotsSince(-1, 4200), [4200]);
  });

  test('adds the next slot during normal playback', () {
    expect(danmakuSlotsSince(4200, 4300), [4300]);
  });

  test('adds the slots skipped at high speed', () {
    // 3x on a 24 fps video: 125 ms a frame
    expect(danmakuSlotsSince(4200, 4500), [4300, 4400, 4500]);
  });

  test('adds up to a second of skipped slots', () {
    expect(danmakuSlotsSince(4000, 5000), hasLength(10));
  });

  test('treats a jump of more than a second as a seek', () {
    expect(danmakuSlotsSince(4000, 5100), [5100]);
  });

  test('treats a jump back as a seek', () {
    expect(danmakuSlotsSince(9000, 3000), [3000]);
  });
}
