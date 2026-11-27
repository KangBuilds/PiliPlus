import 'package:PiliPlus/models/common/video/video_quality.dart';
import 'package:PiliPlus/models/video/play/url.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

class _Box implements Box<dynamic> {
  final stored = <dynamic, dynamic>{};

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      stored[key] ?? defaultValue;

  @override
  bool containsKey(dynamic key) => stored.containsKey(key);

  @override
  Future<void> put(dynamic key, dynamic value) async => stored[key] = value;

  @override
  Future<void> delete(dynamic key) async => stored.remove(key);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final setting = _Box();
  setUpAll(() => GStorage.setting = setting);

  test('自动 is no saved quality, and picks the screen\'s', () async {
    expect(Pref.autoVideoQa, isTrue);
    expect(Pref.defaultVideoQa, Pref.screenVideoQa.code);

    await setting.put(SettingBoxKey.defaultVideoQa, VideoQuality.super8k.code);
    expect(Pref.autoVideoQa, isFalse);
    expect(Pref.defaultVideoQa, VideoQuality.super8k.code);

    await setting.delete(SettingBoxKey.defaultVideoQa);
    expect(Pref.autoVideoQa, isTrue);
    expect(Pref.defaultVideoQa, Pref.screenVideoQa.code);
  });

  test('the default quality is what the screen shows', () {
    // Shorter side in physical pixels; 0 before the screen is known
    for (final side in <double>[0, 750, 1179, 1320, 1488, 1640, 1668]) {
      expect(defaultVideoQualityFor(side), VideoQuality.high1080plus);
    }
    for (final side in <double>[2048, 2064]) {
      expect(defaultVideoQualityFor(side), VideoQuality.super4K);
    }
  });

  test('by default no HDR, Dolby Vision or 60 fps on a phone', () {
    PlayUrlModel offering(List<int> qualities) => PlayUrlModel(
      dash: Dash(
        video: [
          for (final q in qualities)
            VideoItem(id: q, quality: VideoQuality.fromCode(q)),
        ],
      ),
      acceptQuality: qualities,
    );
    final phone = defaultVideoQualityFor(1179).code;
    final ipad = defaultVideoQualityFor(2048).code;

    final vip = offering([127, 126, 125, 120, 116, 112, 80, 64, 32]);
    expect(vip.findAvailableVideoQuality(phone), 112);
    expect(vip.findAvailableVideoQuality(ipad), 120);
    // No 1080P+: 1080P, not 1080P60
    expect(offering([126, 120, 116, 80]).findAvailableVideoQuality(phone), 80);
    // Without VIP the top stream, as before
    expect(offering([80, 64, 32]).findAvailableVideoQuality(phone), 80);
    // On a 4K screen with no 4K, the next best
    expect(offering([126, 116, 112, 80]).findAvailableVideoQuality(ipad), 116);
  });

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
    expect(options['demuxer-max-back-bytes'], '${256 * 0x100000}');
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

  test('off Wi-Fi the cellular buffer applies, a bounded window', () {
    expect(bufferSizeFor(isWiFi: true, wifi: 0, cellular: 64), 0);
    expect(bufferSizeFor(isWiFi: false, wifi: 0, cellular: 64), 64);

    final options = buildBufferOptions(
      bufferSize: bufferSizeFor(isWiFi: false, wifi: 0, cellular: 64),
      bufferSec: 0,
      playbackSpeed: 1,
    );

    expect(options['demuxer-max-bytes'], '${64 * 0x100000}');
    expect(options['demuxer-max-back-bytes'], '${4 * 0x100000}');
  });
}
