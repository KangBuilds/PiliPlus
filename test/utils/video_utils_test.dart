import 'package:PiliPlus/models/common/video/cdn_type.dart';
import 'package:PiliPlus/utils/video_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
