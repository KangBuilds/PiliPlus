import 'package:PiliPlus/models/common/video/cdn_type.dart';
import 'package:PiliPlus/utils/video_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats playback info values', () {
    expect(VideoUtils.formatBitrate('2842000'), '2842 Kbps');
    expect(VideoUtils.formatBitrate(''), '—');
    expect(VideoUtils.formatFrameRate('29.966'), '@29.966');
    expect(VideoUtils.formatFrameRate('60'), '@60.000');
    expect(VideoUtils.formatFrameRate(''), isEmpty);
    expect(
      VideoUtils.hostOf('https://cn-hk-eq-01-03.bilivideo.com/file.m4s'),
      'cn-hk-eq-01-03.bilivideo.com',
    );
    expect(VideoUtils.hostOf('/local/file.m4s'), isEmpty);
  });

  test('selects an automatic or fetched CDN host', () {
    const urls = [
      'https://a.mcdn.bilivideo.com/v1/resource/file.m4s',
      'https://cn-hk-eq-bcache-01.bilivideo.com/file.m4s',
    ];

    expect(
      VideoUtils.getCdnUrl(
        urls,
        defaultCDNService: CDNService.auto,
      ),
      urls.last,
    );
    expect(
      Uri.parse(
        VideoUtils.getCdnUrl(
          urls,
          defaultCDNService: const CDNService(
            'test',
            'upos-sz-mirrorcos.bilivideo.com',
          ),
        ),
      ).host,
      'upos-sz-mirrorcos.bilivideo.com',
    );
  });
}
