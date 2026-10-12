import 'dart:typed_data';

import 'package:PiliPlus/services/thread_ripper/candidates.dart';
import 'package:PiliPlus/services/thread_ripper/host_book.dart';
import 'package:PiliPlus/services/thread_ripper/job.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_cdn.dart';

const _fallback =
    'https://upos-sz-302ppio.bilivideo.com/upgcxcode/11/22/33/33-1-100024.m4s?deadline=9999999999&upsig=abc';

RipperJob _job(
  FakeFetcher fetcher, {
  int start = 0,
  int? end,
  int? total,
  bool racing = true,
  Set<String>? excluded,
}) => RipperJob(
  candidates: mediaCandidates([kListedUrl]),
  fallback: Uri.parse(_fallback),
  start: start,
  requestedEnd: end,
  total: total,
  book: HostBook(),
  fetcher: fetcher,
  excluded: excluded ?? {},
  racing: () => racing,
  config: testConfig,
);

Future<Uint8List> _drain(RipperJob job) async {
  final out = BytesBuilder(copy: false);
  while (true) {
    final chunk = await job.next();
    if (chunk == null) return out.takeBytes();
    out.add(chunk);
  }
}

void main() {
  test('assembles an open-ended range in order from many hosts', () async {
    final data = testFile(100 * 1024 + 123);
    final fetcher = FakeFetcher(
      data,
      otherHosts: const FakeHost(chunkDelay: Duration(milliseconds: 1)),
    );
    final job = _job(fetcher);

    expect(await job.begin(), data.length);
    expect(await _drain(job), data);
    final hosts = {for (final (host, _) in fetcher.requests) host};
    expect(hosts.length, greaterThan(2));
    expect(hosts, isNot(contains('upos-sz-302ppio.bilivideo.com')));
  });

  test('serves a middle range with a known size', () async {
    final data = testFile(64 * 1024);
    final job = _job(
      FakeFetcher(data),
      start: 5000,
      end: 40000,
      total: data.length,
    );

    expect(await job.begin(), data.length);
    expect(await _drain(job), data.sublist(5000, 40001));
  });

  test('a file smaller than the first piece ends where it ends', () async {
    final data = testFile(300);
    final job = _job(FakeFetcher(data));

    expect(await job.begin(), 300);
    expect(await _drain(job), data);
  });

  test('races around hosts that never answer or stall', () async {
    final data = testFile(48 * 1024);
    final fetcher = FakeFetcher(
      data,
      hosts: {
        'upos-sz-mirrorali.bilivideo.com': const FakeHost(hang: true),
        'upos-sz-mirrorhw.bilivideo.com': const FakeHost(hang: true),
        'upos-sz-mirrorbos.bilivideo.com': const FakeHost(
          chunk: 512,
          chunkDelay: Duration(seconds: 5),
        ),
      },
    );
    final job = _job(fetcher);

    final watch = Stopwatch()..start();
    await job.begin();
    expect(await _drain(job), data);
    expect(watch.elapsedMilliseconds, lessThan(3000));
  });

  test(
    'drops hosts with another version of the file, or no range support',
    () async {
      final data = testFile(40 * 1024);
      final excluded = <String>{};
      final fetcher = FakeFetcher(
        data,
        hosts: {
          'upos-sz-mirrorali.bilivideo.com': const FakeHost(total: 999999),
          'upos-sz-mirrorhw.bilivideo.com': const FakeHost(status: 200),
          'upos-sz-mirrorbos.bilivideo.com': const FakeHost(status: 404),
        },
      );
      final job = _job(fetcher, total: data.length, excluded: excluded);

      await job.begin();
      expect(await _drain(job), data);
      expect(
        excluded,
        containsAll([
          'upos-sz-mirrorali.bilivideo.com',
          'upos-sz-mirrorhw.bilivideo.com',
          'upos-sz-mirrorbos.bilivideo.com',
        ]),
      );
    },
  );

  test('retries a body that breaks off on another host', () async {
    final data = testFile(32 * 1024);
    final fetcher = FakeFetcher(
      data,
      hosts: {
        for (final host in seedHosts.take(4))
          host: const FakeHost(breakAfter: 1024),
      },
    );
    final job = _job(fetcher, total: data.length);

    await job.begin();
    expect(await _drain(job), data);
  });

  test('falls back to the player URL when every host refuses', () async {
    final data = testFile(20 * 1024);
    final fetcher = FakeFetcher(
      data,
      hosts: {'upos-sz-302ppio.bilivideo.com': const FakeHost()},
      otherHosts: FakeHost.refusing,
    );
    final job = _job(fetcher, total: data.length);

    await job.begin();
    expect(await _drain(job), data);
    expect(
      fetcher.requests.where((r) => r.$1 == 'upos-sz-302ppio.bilivideo.com'),
      isNotEmpty,
    );
  });

  test('fails when the fallback fails as well', () async {
    final fetcher = FakeFetcher(testFile(8192), otherHosts: FakeHost.refusing);
    final job = _job(fetcher);

    await expectLater(job.begin(), throwsA(isA<RipperJobFailed>()));
    await expectLater(job.next(), throwsA(isA<RipperJobFailed>()));
  });

  test('never duplicates a piece when racing is off', () async {
    final data = testFile(64 * 1024);
    final fetcher = FakeFetcher(
      data,
      otherHosts: const FakeHost(ttfb: Duration(milliseconds: 150)),
    );
    final job = _job(fetcher, total: data.length, racing: false);

    await job.begin();
    expect(await _drain(job), data);
    final starts = [for (final (_, range) in fetcher.requests) range.start];
    expect(starts.toSet().length, starts.length);
  });

  test('cancel stops every attempt', () async {
    final data = testFile(1024 * 1024);
    final fetcher = FakeFetcher(
      data,
      otherHosts: const FakeHost(chunkDelay: Duration(milliseconds: 20)),
    );
    final job = _job(fetcher, total: data.length);

    await job.begin();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    job.cancel();
    await expectLater(job.next(), throwsA(isA<RipperJobFailed>()));
    final count = fetcher.requests.length;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(fetcher.requests.length, count);
  });
}
