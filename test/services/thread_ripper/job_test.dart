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
  group('phase 2', phase2);

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

void phase2() {
  const onePiece = RipperConfig(
    firstPiece: 1024,
    minPiece: 64 * 1024,
    maxPiece: 64 * 1024,
    pieceMs: 10,
    headTtfbMs: 60,
    ttfbMs: 120,
    headStallMs: 60,
    stallMs: 120,
    giveUpMs: 2000,
    laggardBytes: 4096,
    probeBytes: 8192,
    stealMin: 4096,
    tickMs: 10,
  );

  RipperJob job(
    FakeFetcher fetcher,
    RipperConfig config, {
    bool racing = true,
  }) => RipperJob(
    candidates: mediaCandidates([kListedUrl]),
    fallback: Uri.parse(_fallback),
    start: 0,
    requestedEnd: null,
    total: fetcher.data.length,
    book: HostBook(),
    fetcher: fetcher,
    excluded: {},
    racing: () => racing,
    config: config,
  );

  test('hands out the head piece as it fills', () async {
    final data = testFile(64 * 1024);
    final fetcher = FakeFetcher(
      data,
      otherHosts: const FakeHost(
        chunk: 1024,
        chunkDelay: Duration(milliseconds: 15),
      ),
    );
    final ripper = job(fetcher, onePiece, racing: false);
    await ripper.begin();

    final watch = Stopwatch()..start();
    final first = (await ripper.next())!;
    // The whole piece takes about a second
    expect(watch.elapsedMilliseconds, lessThan(400));
    expect(first.length, lessThan(data.length));
    expect(first, data.sublist(0, first.length));
    final rest = await _drain(ripper);
    expect([...first, ...rest], data);
  });

  test(
    'cuts a racer that fell behind, and races the leader once it stalls',
    () async {
      final data = testFile(64 * 1024);
      final fetcher = FakeFetcher(
        data,
        hosts: {
          // Listed, owns the piece: fast, then silent before the end
          'upos-sz-mirrorali.bilivideo.com': const FakeHost(
            chunk: 4096,
            stallAfter: 60 * 1024,
          ),
          // The head racer: slow
          'upos-sz-mirrorhw.bilivideo.com': const FakeHost(
            chunk: 1024,
            chunkDelay: Duration(milliseconds: 20),
          ),
        },
      );
      final ripper = job(fetcher, onePiece);
      await ripper.begin();

      expect(await _drain(ripper), data);
      expect(
        fetcher.delivered['upos-sz-mirrorhw.bilivideo.com'] ?? 0,
        lessThan(16 * 1024),
      );
      // The stalled tail went to a third host, from where the leader stopped
      expect(
        fetcher.requests.where(
          (r) =>
              r.$1 != 'upos-sz-mirrorali.bilivideo.com' &&
              r.$1 != 'upos-sz-mirrorhw.bilivideo.com' &&
              r.$2.start == 60 * 1024,
        ),
        isNotEmpty,
      );
    },
  );

  test('splits the tail of a slow piece off to another host', () async {
    final data = testFile(64 * 1024);
    final fetcher = FakeFetcher(
      data,
      hosts: {
        'upos-sz-mirrorali.bilivideo.com': const FakeHost(
          chunk: 1024,
          chunkDelay: Duration(milliseconds: 10),
        ),
      },
      otherHosts: const FakeHost(chunk: 4096),
    );
    // No racing: any second host on the piece is a split
    final ripper = job(fetcher, onePiece, racing: false);
    await ripper.begin();

    final watch = Stopwatch()..start();
    expect(await _drain(ripper), data);
    final split = fetcher.requests.where(
      (r) => r.$1 != 'upos-sz-mirrorali.bilivideo.com',
    );
    expect(split, isNotEmpty);
    expect(split.first.$2.start, greaterThan(0));
    expect(split.first.$2.end, data.length - 1);
    // The slow host alone takes about 640 ms
    expect(watch.elapsedMilliseconds, lessThan(500));
    // Nothing was fetched twice beyond what was in flight at the split
    final fetched = fetcher.delivered.values.fold(0, (a, b) => a + b);
    expect(fetched, lessThan(data.length + 8 * 1024));
  });

  test('idle slots measure hosts never measured', () async {
    final data = testFile(256 * 1024);
    final fetcher = FakeFetcher(
      data,
      otherHosts: const FakeHost(
        chunk: 1024,
        chunkDelay: Duration(milliseconds: 2),
      ),
    );
    final ripper = job(
      fetcher,
      const RipperConfig(
        firstPiece: 1024,
        minPiece: 32 * 1024,
        maxPiece: 32 * 1024,
        maxPiecesAhead: 3,
        jobInflight: 6,
        headTtfbMs: 1000,
        ttfbMs: 1000,
        headStallMs: 1000,
        stallMs: 1000,
        probeBytes: 4096,
        laggardBytes: 4096,
        tickMs: 10,
      ),
    );
    await ripper.begin();

    expect(await _drain(ripper), data);
    // A probe starts where an owner is: the same bytes on another host
    final byStart = <int, Set<String>>{};
    for (final (host, range) in fetcher.requests) {
      (byStart[range.start] ??= {}).add(host);
    }
    expect(
      byStart.entries.where((e) => e.key != 0 && e.value.length > 1),
      isNotEmpty,
    );
  });
}
