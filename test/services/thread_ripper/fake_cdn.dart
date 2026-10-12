import 'dart:async';
import 'dart:typed_data';

import 'package:PiliPlus/services/thread_ripper/fetcher.dart';
import 'package:PiliPlus/services/thread_ripper/job.dart';
import 'package:PiliPlus/services/thread_ripper/range.dart';

const kListedUrl =
    'https://upos-sz-mirrorali.bilivideo.com/upgcxcode/11/22/33/33-1-100024.m4s?deadline=9999999999&upsig=abc&os=alibv';

const testConfig = RipperConfig(
  firstPiece: 1024,
  minPiece: 4096,
  maxPiece: 8192,
  pieceMs: 10,
  maxPiecesAhead: 6,
  maxBytesAhead: 64 * 1024,
  headTtfbMs: 60,
  ttfbMs: 120,
  headStallMs: 60,
  stallMs: 120,
  giveUpMs: 600,
  tickMs: 10,
);

Uint8List testFile(int length) =>
    Uint8List.fromList(List.generate(length, (i) => (i * 31 + 7) & 0xff));

/// How one fake CDN host behaves.
class FakeHost {
  const FakeHost({
    this.ttfb = Duration.zero,
    this.chunk = 2048,
    this.chunkDelay = Duration.zero,
    this.status,
    this.total,
    this.hang = false,
    this.breakAfter,
    this.failFrom,
  });

  static const refusing = FakeHost(status: 403);

  final Duration ttfb;
  final int chunk;
  final Duration chunkDelay;

  /// Answers with this status, no body.
  final int? status;

  /// Claims another total size (another version of the file).
  final int? total;

  /// Never answers.
  final bool hang;

  /// The body breaks off after this many bytes.
  final int? breakAfter;

  /// Refuses (403) every range starting at or past this offset.
  final int? failFrom;
}

class FakeFetcher implements RangeFetcher {
  FakeFetcher(
    this.data, {
    this.hosts = const {},
    this.otherHosts = const FakeHost(),
  });

  final Uint8List data;
  final Map<String, FakeHost> hosts;
  final FakeHost otherHosts;
  final requests = <(String, ByteRange)>[];
  final delivered = <String, int>{};

  @override
  Future<RangeResponse> fetch(
    Uri uri,
    ByteRange range,
    CancelSignal cancel,
  ) async {
    requests.add((uri.host, range));
    final host = hosts[uri.host] ?? otherHosts;
    final canceled = Completer<void>();
    cancel.onCancel(() {
      if (!canceled.isCompleted) canceled.complete();
    });
    if (host.hang) {
      await canceled.future;
      throw StateError('aborted');
    }
    await Future.any([Future<void>.delayed(host.ttfb), canceled.future]);
    if (cancel.isCanceled) throw StateError('aborted');
    final failFrom = host.failFrom;
    final status =
        host.status ??
        (failFrom != null && range.start >= failFrom ? 403 : null);
    if (status != null) {
      return RangeResponse(
        status: status,
        contentRange: null,
        body: const Stream.empty(),
      );
    }
    if (range.start >= data.length) {
      return const RangeResponse(
        status: 416,
        contentRange: null,
        body: Stream.empty(),
      );
    }
    final end = range.end < data.length ? range.end : data.length - 1;
    return RangeResponse(
      status: 206,
      contentRange: ContentRange(range.start, end, host.total ?? data.length),
      contentType: 'video/mp4',
      body: _body(uri.host, host, range.start, end, cancel),
    );
  }

  Stream<List<int>> _body(
    String name,
    FakeHost host,
    int start,
    int end,
    CancelSignal cancel,
  ) async* {
    var sent = 0;
    for (var pos = start; pos <= end; pos += host.chunk) {
      if (host.chunkDelay > Duration.zero) {
        await Future<void>.delayed(host.chunkDelay);
      }
      if (cancel.isCanceled) throw StateError('aborted');
      if (host.breakAfter case final limit? when sent >= limit) {
        throw StateError('connection reset');
      }
      final stop = pos + host.chunk - 1 < end ? pos + host.chunk - 1 : end;
      final chunk = data.sublist(pos, stop + 1);
      sent += chunk.length;
      delivered[name] = (delivered[name] ?? 0) + chunk.length;
      yield chunk;
    }
  }
}
