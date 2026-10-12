import 'package:PiliPlus/services/thread_ripper/candidates.dart';
import 'package:PiliPlus/services/thread_ripper/range.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_cdn.dart';

void main() {
  group('range', () {
    test('parses the Range headers mpv sends', () {
      expect(parseRangeHeader('bytes=0-'), (start: 0, end: null));
      expect(parseRangeHeader('bytes=100-199'), (start: 100, end: 199));
      expect(parseRangeHeader('bytes=-500'), isNull);
      expect(parseRangeHeader('bytes=0-1,5-9'), isNull);
      expect(parseRangeHeader('bytes=9-1'), isNull);
    });

    test('parses Content-Range', () {
      final range = parseContentRange('bytes 0-1023/4096')!;
      expect((range.start, range.end, range.total), (0, 1023, 4096));
      expect(parseContentRange('bytes 0-1023/*')!.total, isNull);
      expect(parseContentRange('bytes 0-4096/4096'), isNull);
      expect(parseContentRange(null), isNull);
    });

    test('classifies responses', () {
      const expected = ByteRange(0, 1023);
      ResponseVerdict verdict(int status, String? range, [int? total]) =>
          classifyResponse(
            status: status,
            contentRange: parseContentRange(range),
            expected: expected,
            expectedTotal: total,
          );

      expect(verdict(206, 'bytes 0-1023/4096').outcome, MediaOutcome.ok);
      expect(verdict(206, 'bytes 0-1023/4096').total, 4096);
      expect(
        verdict(206, 'bytes 0-1023/4096', 5000).outcome,
        MediaOutcome.staleObject,
      );
      expect(verdict(206, 'bytes 1-1023/4096').outcome, MediaOutcome.badRange);
      expect(verdict(206, 'bytes 0-99/100').outcome, MediaOutcome.eofClamp);
      expect(verdict(206, null).outcome, MediaOutcome.unverifiable);
      expect(verdict(200, null).outcome, MediaOutcome.noRange);
      expect(verdict(403, null).outcome, MediaOutcome.refused);
      expect(verdict(429, null).outcome, MediaOutcome.throttled);
    });
  });

  group('candidates', () {
    test('listed hosts first, then the signature on every seed mirror', () {
      final candidates = mediaCandidates([kListedUrl]);
      expect(candidates.first.uri.toString(), kListedUrl);
      expect(candidates.first.listed, isTrue);
      final hosts = candidates.map((c) => c.host).toList();
      expect(hosts.toSet().length, hosts.length);
      expect(hosts, containsAll(seedHosts));
      for (final c in candidates.skip(1)) {
        expect(c.listed, isFalse);
        expect(c.uri.path, Uri.parse(kListedUrl).path);
        expect(c.uri.query, Uri.parse(kListedUrl).query);
      }
    });

    test('P2P addresses are never candidates, their signature still moves', () {
      final candidates = mediaCandidates([
        'https://upos-sz-302ppio.bilivideo.com/upgcxcode/1/2/3.m4s?upsig=a',
        'https://xy1x2x3x4xy.mcdn.bilivideo.cn:4483/upgcxcode/1/2/3.m4s?upsig=a',
        'https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/1/2/3.m4s?upsig=a&os=mcdn',
      ]);
      expect(candidates.any((c) => isP2PCdnHost(c.host)), isFalse);
      expect(candidates.every((c) => !c.listed), isTrue);
      expect(candidates.map((c) => c.host), containsAll(seedHosts));
    });

    test('Akamai signatures stay on Akamai', () {
      final candidates = mediaCandidates([
        'https://upos-hz-mirrorakam.akamaized.net/upgcxcode/1/2/3.m4s?hdnts=exp=1~hmac=x',
      ]);
      expect(candidates.map((c) => c.host), [
        'upos-hz-mirrorakam.akamaized.net',
      ]);
    });

    test('a 302 PCDN redirect target counts as P2P', () {
      // Where upos-sz-302kodo.bilivideo.com actually sends a request
      expect(
        isP2PUrl(
          Uri.parse(
            'https://1865651221.qrstuvwxyzab.com:22443/upos-sz-302kodo.bilivideo.com/upgcxcode/1/2/3.m4s',
          ),
        ),
        isTrue,
      );
      expect(isP2PUrl(Uri.parse(kListedUrl)), isFalse);
    });
  });
}
