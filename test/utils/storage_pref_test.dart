import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preloads the whole video by default', () {
    final options = buildBufferOptions(
      bufferSize: 0,
      bufferSec: 0,
      playbackSpeed: 1,
    );

    expect(options['cache-on-disk'], 'yes');
    expect(options['demuxer-cache-unlink-files'], 'immediate');
    expect(options.containsKey('cache-secs'), false);
    expect(options['demuxer-max-bytes'], '${1 << 30}');
    expect(options['demuxer-max-back-bytes'], '${1 << 30}');
  });

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
