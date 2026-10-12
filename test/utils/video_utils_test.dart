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

  group('getCdnUrl', () {
    const path = '/upgcxcode/11/22/33/33-1-100024.m4s';
    const upos = '$path?deadline=9999999999&upsig=abc&os=bcache';
    const bcache = 'https://cn-hk-eq-bcache-01.bilivideo.com$upos';
    const mirror = 'https://upos-sz-mirrorali.bilivideo.com$upos';
    const akamai =
        'https://upos-hz-mirrorakam.akamaized.net$path?upsig=x&hdnts=exp=1~hmac=y';
    const pcdn302 = 'https://upos-sz-302ppio.bilivideo.com$upos';
    const mcdnUpos =
        'https://upos-sz-mirrorcos.bilivideo.com$path?upsig=abc&os=mcdn';
    const ipNode = 'https://203.0.113.7:4483$upos';
    const mcdnTf =
        'https://xy1x2x3x4xy.mcdn.bilivideo.cn:4483/v1/resource/33.m4s?x=1';

    String pick(List<String> urls, {String? host, bool isAudio = false}) {
      VideoUtils.disableAudioCDN = false;
      return VideoUtils.getCdnUrl(
        urls,
        defaultCDNService: host == null
            ? CDNService.auto
            : CDNService(host, host),
        isAudio: isAudio,
      );
    }

    test(
      'prefers Bilibili hosts, never a P2P node while others are listed',
      () {
        expect(pick([pcdn302, mcdnUpos, ipNode, bcache]), bcache);
        expect(pick([akamai, mirror]), mirror);
        expect(pick([pcdn302, akamai]), akamai);
      },
    );

    test('moves a P2P signature onto a mirror when nothing else is listed', () {
      final rescued = Uri.parse(pick([pcdn302, ipNode]));
      expect(rescued.host, 'upos-sz-mirrorcos.bilivideo.com');
      expect(rescued.path, path);
      expect(rescued.query, Uri.parse(pcdn302).query);
    });

    test('fetches a PCDN resource path through the proxy', () {
      final proxied = Uri.parse(pick([mcdnTf]));
      expect(proxied.host, 'proxy-tf-all-ws.bilivideo.com');
      expect(proxied.queryParameters['url'], mcdnTf);
    });

    test('applies the CDN override to signatures the host accepts', () {
      expect(
        Uri.parse(pick([bcache], host: 'upos-sz-mirrorcos.bilivideo.com')).host,
        'upos-sz-mirrorcos.bilivideo.com',
      );
      // Akamai refuses upos signatures: its own listed address instead
      expect(
        pick([bcache, akamai], host: 'upos-hz-mirrorakam.akamaized.net'),
        akamai,
      );
      // No Akamai address listed: the override cannot apply
      expect(pick([bcache], host: 'upos-hz-mirrorakam.akamaized.net'), bcache);
      // An Akamai signature never goes to an upos host
      expect(
        Uri.parse(pick([akamai], host: 'upos-sz-mirrorcos.bilivideo.com')).host,
        'upos-hz-mirrorakam.akamaized.net',
      );
      // A P2P host saved before it was hidden from the picker is ignored
      expect(pick([bcache], host: 'upos-sz-302kodo.bilivideo.com'), bcache);
    });

    test('leaves audio alone when it does not follow the CDN setting', () {
      VideoUtils.disableAudioCDN = true;
      expect(
        VideoUtils.getCdnUrl(
          [bcache],
          defaultCDNService: const CDNService(
            'test',
            'upos-sz-mirrorcos.bilivideo.com',
          ),
          isAudio: true,
        ),
        bcache,
      );
      VideoUtils.disableAudioCDN = false;
    });
  });
}
