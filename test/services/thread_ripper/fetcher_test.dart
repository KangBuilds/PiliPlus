import 'dart:async';
import 'dart:io';

import 'package:PiliPlus/services/thread_ripper/fetcher.dart';
import 'package:PiliPlus/services/thread_ripper/range.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0)
      ..listen((request) async {
        request.response
          ..bufferOutput = false
          ..statusCode = HttpStatus.partialContent
          ..contentLength = 8192
          ..headers.set(HttpHeaders.contentRangeHeader, 'bytes 0-8191/8192')
          // The server only sends headers with some body: one byte, then the
          // body stalls.
          ..add([0]);
        await request.response.flush();
      });
  });

  tearDown(() => server.close(force: true));

  Future<RangeResponse> fetch(CancelSignal cancel) => HttpRangeFetcher().fetch(
    Uri.parse('http://127.0.0.1:${server.port}/file'),
    const ByteRange(0, 8191),
    cancel,
  );

  test('cancel ends a stalled body after response headers arrived', () async {
    final cancel = CancelSignal();
    final response = await fetch(cancel);
    expect(response.status, HttpStatus.partialContent);
    final ended = Completer<void>();
    final subscription = response.body.listen(
      (_) {},
      onDone: ended.complete,
      onError: ended.completeError,
    );
    addTearDown(subscription.cancel);

    await Future<void>.delayed(Duration.zero);
    cancel.cancel();
    await ended.future.timeout(const Duration(seconds: 1));
  });

  test('cancel before listening also closes the response body', () async {
    final cancel = CancelSignal();
    final response = await fetch(cancel);
    cancel.cancel();

    expect(
      await response.body.toList().timeout(const Duration(seconds: 1)),
      isEmpty,
    );
  });

  test('cancel without ever reading the body frees its connection', () async {
    // What a job does with a response it rejects: cancel, never read. The
    // client allows 6 connections per host: a leak would block the 7th
    final fetcher = HttpRangeFetcher();
    final uri = Uri.parse('http://127.0.0.1:${server.port}/file');
    for (var i = 0; i < 6; i++) {
      final cancel = CancelSignal();
      await fetcher.fetch(uri, const ByteRange(0, 8191), cancel);
      cancel.cancel();
    }

    final response = await fetcher
        .fetch(uri, const ByteRange(0, 8191), CancelSignal())
        .timeout(const Duration(seconds: 2));
    expect(response.status, HttpStatus.partialContent);
  });
}
