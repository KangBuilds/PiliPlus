import 'dart:io';
import 'dart:typed_data';

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
}
