import 'dart:io';
import 'dart:typed_data';

import 'package:PiliPlus/services/thread_ripper/job.dart';
import 'package:PiliPlus/services/thread_ripper/thread_ripper.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_cdn.dart';

void main() {
  late HttpClient client;

  setUp(() => client = HttpClient()..autoUncompress = false);
  tearDown(() => client.close(force: true));

  Future<(HttpClientResponse, Uint8List)> get(
    String url, {
    String? range,
    bool follow = true,
  }) async {
    final request = await client.getUrl(Uri.parse(url));
    request.followRedirects = follow;
    if (range != null) request.headers.set(HttpHeaders.rangeHeader, range);
    final response = await request.close();
    final builder = BytesBuilder(copy: false);
    try {
      await response.forEach(builder.add);
    } on HttpException {
      // A body cut short
    }
    return (response, builder.takeBytes());
  }

  test('serves open-ended and bounded ranges as mpv reads them', () async {
    final data = testFile(90 * 1024 + 17);
    final ripper = ThreadRipper(
      fetcher: FakeFetcher(data),
      config: testConfig,
      wifiOnly: false,
    );
    addTearDown(ripper.close);
    final url = await ripper.wrapNow(kListedUrl);
    expect(url, startsWith('http://127.0.0.1:'));

    final (whole, wholeBody) = await get(url, range: 'bytes=0-');
    expect(whole.statusCode, 206);
    expect(
      whole.headers.value('content-range'),
      'bytes 0-${data.length - 1}/${data.length}',
    );
    expect(whole.contentLength, data.length);
    expect(wholeBody, data);

    final (seek, seekBody) = await get(url, range: 'bytes=50000-');
    expect(seek.statusCode, 206);
    expect(seekBody, data.sublist(50000));

    final (part, partBody) = await get(url, range: 'bytes=100-4195');
    expect(
      part.headers.value('content-range'),
      'bytes 100-4195/${data.length}',
    );
    expect(partBody, data.sublist(100, 4196));

    final (plain, plainBody) = await get(url);
    expect(plain.statusCode, 200);
    expect(plainBody, data);

    final (past, _) = await get(url, range: 'bytes=${data.length}-');
    expect(past.statusCode, 416);
  });

  test('sends mpv to its own URL when no host answers', () async {
    final ripper = ThreadRipper(
      fetcher: FakeFetcher(
        testFile(4096),
        otherHosts: const FakeHost(hang: true),
      ),
      config: testConfig,
      wifiOnly: false,
    );
    addTearDown(ripper.close);
    final url = await ripper.wrapNow(kListedUrl);

    final (response, _) = await get(url, range: 'bytes=0-', follow: false);
    expect(response.statusCode, 302);
    expect(response.headers.value('location'), kListedUrl);
  });

  test('leaves URLs it cannot help alone', () async {
    final ripper = ThreadRipper(
      fetcher: FakeFetcher(testFile(1)),
      wifiOnly: false,
    );
    addTearDown(ripper.close);
    const live = 'https://cn-gotcha01.bilivideo.com/live-bvc/123/live_1.flv';
    expect(await ripper.wrapNow(live), live);
    const akamai =
        'https://upos-hz-mirrorakam.akamaized.net/upgcxcode/1/2/3.m4s?hdnts=exp=1~hmac=x';
    expect(await ripper.wrapNow(akamai), akamai);
  });

  test(
    'cuts the body short when every host and the fallback fail mid-way',
    () async {
      final data = testFile(64 * 1024);
      final ripper = ThreadRipper(
        fetcher: FakeFetcher(data, otherHosts: const FakeHost(failFrom: 20000)),
        config: testConfig,
        wifiOnly: false,
      );
      addTearDown(ripper.close);
      final url = await ripper.wrapNow(kListedUrl);

      final (response, body) = await get(url, range: 'bytes=0-');
      expect(response.statusCode, 206);
      expect(response.contentLength, data.length);
      expect(body.length, lessThan(data.length));
      expect(body, data.sublist(0, body.length));

      // mpv's retry goes straight to its own URL for a while
      final (retry, _) = await get(
        url,
        range: 'bytes=${body.length}-',
        follow: false,
      );
      expect(retry.statusCode, 302);
    },
  );

  test(
    'warms up the head before mpv asks, and reports what it served',
    () async {
      final data = testFile(90 * 1024);
      final fetcher = FakeFetcher(data);
      final ripper = ThreadRipper(
        fetcher: fetcher,
        config: testConfig,
        wifiOnly: false,
      );
      addTearDown(ripper.close);
      final url = await ripper.wrapNow(kListedUrl);
      expect(ripper.isProxyUrl(url), isTrue);
      expect(ripper.isProxyUrl(kListedUrl), isFalse);

      await Future<void>.delayed(const Duration(milliseconds: 100));
      final warmed = fetcher.requests.length;
      expect(warmed, greaterThan(0));
      expect(fetcher.requests.every((r) => r.$2.start == 0), isTrue);

      final (response, body) = await get(url, range: 'bytes=0-');
      expect(response.statusCode, 206);
      expect(body, data);
      // The head came from the warm-up: nothing fetched it again
      expect(
        fetcher.requests.skip(warmed).where((r) => r.$2.start == 0),
        isEmpty,
      );

      final (head, headBody) = await get(url, range: 'bytes=10-99');
      expect(head.statusCode, 206);
      expect(headBody, data.sublist(10, 100));

      final stats = ripper.stats;
      expect(stats.usefulBytes, greaterThanOrEqualTo(data.length));
      expect(stats.fetchedBytes, greaterThanOrEqualTo(stats.usefulBytes));
      expect(stats.servedRate, greaterThan(0));
      expect(stats.hosts, isNotEmpty);
    },
  );

  test('serves the first bytes before the warm-up is complete', () async {
    final data = testFile(256 * 1024);
    final ripper = ThreadRipper(
      fetcher: FakeFetcher(
        data,
        // The 64 KiB warm-up takes over a second
        otherHosts: const FakeHost(
          chunk: 1024,
          chunkDelay: Duration(milliseconds: 20),
        ),
      ),
      config: const RipperConfig(
        firstPiece: 64 * 1024,
        minPiece: 16 * 1024,
        maxPiece: 16 * 1024,
        tickMs: 10,
      ),
      wifiOnly: false,
    );
    addTearDown(ripper.close);
    final url = await ripper.wrapNow(kListedUrl);

    final watch = Stopwatch()..start();
    final (response, body) = await get(url, range: 'bytes=0-99');
    expect(response.statusCode, 206);
    expect(body, data.sublist(0, 100));
    expect(watch.elapsedMilliseconds, lessThan(500));

    final (_, whole) = await get(url, range: 'bytes=0-');
    expect(whole, data);
  });

  test('one deadline: no host answering falls back once, not twice', () async {
    final ripper = ThreadRipper(
      fetcher: FakeFetcher(
        testFile(4096),
        otherHosts: const FakeHost(hang: true),
      ),
      config: testConfig,
      wifiOnly: false,
      commitTimeout: const Duration(milliseconds: 400),
    );
    addTearDown(ripper.close);
    final url = await ripper.wrapNow(kListedUrl);

    final watch = Stopwatch()..start();
    final (response, _) = await get(url, range: 'bytes=0-', follow: false);
    expect(response.statusCode, 302);
    // The warm-up wait and the job's own would add up to 800 ms
    expect(watch.elapsedMilliseconds, lessThan(700));
  });

  test('a file the proxy dropped is rebuilt from its URL', () async {
    final data = testFile(20 * 1024);
    final ripper = ThreadRipper(
      fetcher: FakeFetcher(data),
      config: testConfig,
      wifiOnly: false,
    );
    addTearDown(ripper.close);
    final first = await ripper.wrapNow(kListedUrl);
    for (var i = 0; i < 40; i++) {
      await ripper.wrapNow('$kListedUrl&n=$i');
    }

    final (response, body) = await get(first, range: 'bytes=0-');
    expect(response.statusCode, 206);
    expect(body, data);
  });

  test('headers fast, body slow: mpv goes to its own URL in time', () async {
    final data = testFile(64 * 1024);
    final ripper = ThreadRipper(
      // Every host answers at once, then sends nothing for two seconds
      fetcher: FakeFetcher(
        data,
        otherHosts: const FakeHost(chunkDelay: Duration(seconds: 2)),
      ),
      config: testConfig,
      wifiOnly: false,
      commitTimeout: const Duration(milliseconds: 400),
    );
    addTearDown(ripper.close);
    final url = await ripper.wrapNow(kListedUrl);

    for (final range in ['bytes=0-', 'bytes=40000-']) {
      final watch = Stopwatch()..start();
      final (response, _) = await get(url, range: range, follow: false);
      expect(response.statusCode, 302, reason: range);
      expect(watch.elapsedMilliseconds, lessThan(1000), reason: range);
    }
  });

  test('HEAD reports the range without waiting for bytes', () async {
    final data = testFile(64 * 1024);
    final ripper = ThreadRipper(
      fetcher: FakeFetcher(
        data,
        otherHosts: const FakeHost(chunkDelay: Duration(seconds: 2)),
      ),
      config: testConfig,
      wifiOnly: false,
    );
    addTearDown(ripper.close);
    final url = await ripper.wrapNow(kListedUrl);

    final request = await client.headUrl(Uri.parse(url));
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=100-');
    final watch = Stopwatch()..start();
    final response = await request.close();
    await response.drain<void>();
    expect(response.statusCode, 206);
    expect(response.contentLength, data.length - 100);
    expect(watch.elapsedMilliseconds, lessThan(1000));
  });

  group('after iOS took the socket away', () {
    Future<(ThreadRipper, String, Uint8List)> lost() async {
      final data = testFile(20 * 1024);
      final ripper = ThreadRipper(
        fetcher: FakeFetcher(data),
        config: testConfig,
        wifiOnly: false,
      );
      addTearDown(ripper.close);
      final url = await ripper.wrapNow(kListedUrl);
      expect((await get(url, range: 'bytes=0-')).$2, data);
      await ripper.loseSocket();
      // A fresh client: a pooled connection would fail differently
      client.close(force: true);
      client = HttpClient()..autoUncompress = false;
      await expectLater(
        get(url, range: 'bytes=0-'),
        throwsA(isA<SocketException>()),
      );
      return (ripper, url, data);
    }

    test('new URLs are served by a live server again', () async {
      final (ripper, url, data) = await lost();
      final fresh = await ripper.wrapNow(kListedUrl);
      expect((await get(fresh, range: 'bytes=0-')).$2, data);
      // On the same port: what mpv holds works again too
      expect(Uri.parse(fresh).port, Uri.parse(url).port);
      expect((await get(url, range: 'bytes=0-')).$2, data);
    });

    test('coming back to the foreground revives it', () async {
      final (ripper, url, data) = await lost();
      ripper.revive();
      for (var i = 0; i < 50; i++) {
        try {
          expect((await get(url, range: 'bytes=0-')).$2, data);
          return;
        } on SocketException {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      }
      fail('not revived');
    });
  });

  test('a failed job says why', () async {
    final reports = <String>[];
    final ripper = ThreadRipper(
      fetcher: FakeFetcher(
        testFile(64 * 1024),
        otherHosts: const FakeHost(failFrom: 20000),
      ),
      config: testConfig,
      wifiOnly: false,
      report: reports.add,
    );
    addTearDown(ripper.close);
    final url = await ripper.wrapNow(kListedUrl);

    await get(url, range: 'bytes=0-');
    expect(reports, hasLength(1));
    expect(reports.single, contains('no host could deliver'));
    expect(reports.single, contains('upos-sz-mirrorali.bilivideo.com refused'));
  });
}
