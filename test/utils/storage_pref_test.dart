import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('scales forward buffer with playback speed', () {
    final options = buildBufferOptions(
      bufferSize: 16,
      bufferSec: 16,
      playbackSpeed: 2,
    );

    expect(options['cache-secs'], '32.000');
    expect(options['demuxer-hysteresis-secs'], '4.000');
    expect(options['demuxer-max-bytes'], '${32 * 0x100000}');
    expect(options['demuxer-max-back-bytes'], '${4 * 0x100000}');
  });
}
