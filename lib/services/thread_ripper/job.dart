// The serve loop of Make-Bilibili-Great-Than-Ever-Before's thread-ripper
// (MIT, SukkaW), reduced for a native player that reads one open-ended range:
//
// - Pieces: the range is cut into pieces of about a second of transfer each,
//   fetched a window ahead of what the player reads.
// - Owners: a piece goes to the host expected to finish it first.
// - Races: the piece the player waits on starts on two hosts; any piece with
//   no first byte or stalled gets a racer on another host. The first to
//   finish wins, the others are canceled.
// - Failure: retried on other hosts, then on the player's own URL; after that
//   the job fails.

import 'dart:async';
import 'dart:collection';
import 'dart:math' show max, min;
import 'dart:typed_data';

import 'package:PiliPlus/services/thread_ripper/candidates.dart';
import 'package:PiliPlus/services/thread_ripper/fetcher.dart';
import 'package:PiliPlus/services/thread_ripper/host_book.dart';
import 'package:PiliPlus/services/thread_ripper/range.dart';

const _kib = 1024;
const _mib = 1024 * _kib;

class RipperConfig {
  const RipperConfig({
    this.firstPiece = 256 * _kib,
    this.minPiece = 512 * _kib,
    this.maxPiece = 4 * _mib,
    this.pieceMs = 1000,
    this.maxPiecesAhead = 8,
    this.maxBytesAhead = 16 * _mib,
    this.jobInflight = 8,
    this.globalInflight = 24,
    this.hostInflight = 4,
    this.maxRacers = 3,
    this.maxTries = 6,
    this.headTtfbMs = 700,
    this.ttfbMs = 1500,
    this.headStallMs = 800,
    this.stallMs = 1500,
    this.giveUpMs = 8000,
    this.tickMs = 100,
  });

  /// The first piece of a job whose file size is unknown: small, it is about
  /// latency.
  final int firstPiece;
  final int minPiece;
  final int maxPiece;

  /// A piece is about this long a transfer at the typical host rate.
  final int pieceMs;
  final int maxPiecesAhead;
  final int maxBytesAhead;
  final int jobInflight;
  final int globalInflight;
  final int hostInflight;

  /// Attempts on one piece at once.
  final int maxRacers;

  /// Failed attempts on a piece before it goes to the player's own URL.
  final int maxTries;

  /// No first byte for this long: a racer goes on. The head piece is the one
  /// the player waits on, it is helped sooner.
  final int headTtfbMs;
  final int ttfbMs;

  /// Bytes stopped for this long: a racer goes on.
  final int headStallMs;
  final int stallMs;

  /// No first byte, or no byte, for this long: the attempt is given up.
  final int giveUpMs;
  final int tickMs;
}

class RipperJobFailed implements Exception {
  const RipperJobFailed(this.message);

  final String message;

  @override
  String toString() => 'RipperJobFailed: $message';
}

class _Piece {
  _Piece(this.start, this.end);

  final int start;
  int end;
  Uint8List? data;
  final attempts = <_Attempt>{};

  /// Hosts tried for it, so a retry goes elsewhere.
  final tried = <String>{};
  int tries = 0;
  bool fallbackTried = false;

  int get length => end - start + 1;
  bool get done => data != null;
}

class _Attempt {
  _Attempt(
    this.piece,
    this.uri,
    this.host,
    this.startedAt, {
    this.fallback = false,
  });

  final _Piece piece;
  final Uri uri;
  final String host;
  final int startedAt;
  final bool fallback;
  final cancel = CancelSignal();
  int firstByteAt = 0;
  int lastByteAt = 0;
  int received = 0;

  /// Arrives with the headers: left out of speed samples.
  int firstChunk = 0;

  /// Given up by us, which is a failure of its host, unlike a lost race.
  bool timedOut = false;
}

/// Fetches one byte range of one file from many hosts, and hands it out in
/// order with [next].
class RipperJob {
  RipperJob({
    required this.candidates,
    required this.fallback,
    required this.start,
    required this.requestedEnd,
    required this.book,
    required this.fetcher,
    required this.excluded,
    int? total,
    this.racing = _always,
    this.config = const RipperConfig(),
    this.onTotal,
  }) : _total = total {
    if (total != null) _setEnd(total);
    // Nobody may be waiting for it when the job is canceled
    _totalKnown.future.ignore();
  }

  static bool _always() => true;

  final List<MediaCandidate> candidates;

  /// The URL the player would have used: the last resort.
  final Uri fallback;
  final int start;
  final int? requestedEnd;
  final HostBook book;
  final RangeFetcher fetcher;

  /// Hosts without this file, shared by every job of it.
  final Set<String> excluded;

  /// Whether duplicates may be started (Wi-Fi).
  final bool Function() racing;
  final RipperConfig config;
  final void Function(int total, String? contentType)? onTotal;

  int? _total;
  int? _end;
  String? contentType;
  int _nextOffset = -1;
  int _inflight = 0;
  final _window = Queue<_Piece>();
  Object? _error;
  bool _closed = false;
  bool _handedOut = false;
  Timer? _ticker;
  Completer<void>? _changed;
  final _totalKnown = Completer<int>();

  int? get total => _total;

  /// Starts fetching; completes with the file's total size once a host
  /// confirmed it.
  Future<int> begin() {
    if (_closed) return Future.error(const RipperJobFailed('canceled'));
    if (_nextOffset == -1) {
      _nextOffset = start;
      if (_total case final total?) {
        if (start >= total) {
          return Future.error(const RipperJobFailed('range not satisfiable'));
        }
        _totalKnown.complete(total);
      } else {
        // Size unknown: only one small piece, raced, until a host tells it
        final end = start + config.firstPiece - 1;
        _window.add(
          _Piece(start, requestedEnd == null ? end : min(end, requestedEnd!)),
        );
        _nextOffset = _window.last.end + 1;
      }
      _ticker = Timer.periodic(
        Duration(milliseconds: config.tickMs),
        (_) => _pump(),
      );
      _pump();
    }
    return _totalKnown.future;
  }

  /// The next bytes in order; `null` once the range is complete.
  Future<Uint8List?> next() async {
    while (true) {
      if (_error case final error?) throw error;
      if (_closed) throw const RipperJobFailed('canceled');
      if (_window.isNotEmpty && _window.first.done) {
        final piece = _window.removeFirst();
        _handedOut = true;
        _pump();
        return piece.data;
      }
      if (_end != null && _window.isEmpty && _nextOffset > _end!) return null;
      await (_changed ??= Completer<void>()).future;
    }
  }

  void cancel() {
    if (_closed) return;
    _closed = true;
    _ticker?.cancel();
    for (final piece in _window) {
      for (final attempt in piece.attempts) {
        attempt.cancel.cancel();
      }
    }
    if (!_totalKnown.isCompleted) {
      _totalKnown.completeError(const RipperJobFailed('canceled'));
    }
    _signal();
  }

  void _fail(String message) {
    if (_closed) return;
    _error = RipperJobFailed(message);
    if (!_totalKnown.isCompleted) _totalKnown.completeError(_error!);
    cancel();
  }

  void _signal() {
    final changed = _changed;
    _changed = null;
    changed?.complete();
  }

  void _setEnd(int total) {
    _total = total;
    _end = min(requestedEnd ?? total - 1, total - 1);
  }

  int get _pieceSize => (book.typicalRate * config.pieceMs).round().clamp(
    config.minPiece,
    config.maxPiece,
  );

  void _plan() {
    final end = _end;
    if (end == null) return;
    var ahead = 0;
    for (final piece in _window) {
      ahead += piece.length;
    }
    while (_nextOffset <= end &&
        _window.length < config.maxPiecesAhead &&
        ahead < config.maxBytesAhead) {
      final piece = _Piece(_nextOffset, min(_nextOffset + _pieceSize - 1, end));
      _window.add(piece);
      ahead += piece.length;
      _nextOffset = piece.end + 1;
    }
  }

  bool get _slotFree =>
      _inflight < config.jobInflight && book.inflight < config.globalInflight;

  void _pump() {
    if (_closed) return;
    _plan();
    final now = book.clock();

    for (final piece in _window) {
      for (final a in piece.attempts) {
        final silentFor =
            now - (a.firstByteAt == 0 ? a.startedAt : a.lastByteAt);
        if (silentFor > config.giveUpMs && !a.timedOut) {
          a
            ..timedOut = true
            ..cancel.cancel();
        }
      }
    }

    // Owners: every piece without an attempt gets one, in order
    for (final piece in _window) {
      if (piece.done || piece.attempts.isNotEmpty) continue;
      if (!_slotFree) break;
      if (!_launch(piece)) return;
    }

    if (!racing()) return;

    // Races
    var isHead = true;
    for (final piece in _window) {
      final head = isHead;
      isHead = false;
      if (piece.done || piece.attempts.isEmpty) continue;
      if (piece.attempts.length >= config.maxRacers) continue;
      if (piece.attempts.any((a) => a.fallback)) continue;
      if (!_slotFree) break;
      if (_needsRacer(piece, head, now)) {
        for (final a in piece.attempts) {
          if (a.firstByteAt == 0) book.recordWait(a.host, now - a.startedAt);
        }
        _launch(piece, racer: true);
      }
    }
  }

  bool _needsRacer(_Piece piece, bool head, int now) {
    // What the player waits on first (after opening or seeking) starts on two
    // hosts at once
    if (head && !_handedOut && piece.attempts.length < 2) return true;
    final ttfbLimit = max(
      head ? config.headTtfbMs : config.ttfbMs,
      (book.typicalTtfb * 3).round(),
    );
    final stallLimit = head ? config.headStallMs : config.stallMs;
    return piece.attempts.every((a) {
      if (a.firstByteAt == 0) return now - a.startedAt > ttfbLimit;
      return now - a.lastByteAt > stallLimit;
    });
  }

  /// Starts an attempt on [piece]; `false` when the job failed meanwhile.
  bool _launch(_Piece piece, {bool racer = false}) {
    final (candidate, waitable) = _choose(piece);
    if (candidate != null) {
      _start(_Attempt(piece, candidate.uri, candidate.host, book.clock()));
      return true;
    }
    if (racer || piece.attempts.isNotEmpty) return true;
    // Hosts are left, only busy with other pieces: wait for the next tick
    if (waitable) return true;
    if (!piece.fallbackTried) {
      piece.fallbackTried = true;
      _start(
        _Attempt(piece, fallback, fallback.host, book.clock(), fallback: true),
      );
      return true;
    }
    _fail('no host could deliver ${piece.start}-${piece.end}');
    return false;
  }

  /// The host expected to finish [piece] first, and whether, when there is
  /// none, one may free up for it.
  (MediaCandidate?, bool) _choose(_Piece piece) {
    if (piece.tries >= config.maxTries) return (null, false);
    final busy = {for (final a in piece.attempts) a.host};
    final pool = [
      for (final c in candidates)
        if (!excluded.contains(c.host) &&
            !busy.contains(c.host) &&
            !book.isCoolingDown(c.host))
          c,
    ];
    if (pool.isEmpty) return (null, false);
    var untried = pool.where((c) => !piece.tried.contains(c.host)).toList();
    if (untried.isEmpty) {
      // Every host was tried: a new round
      piece.tried.removeWhere((host) => !busy.contains(host));
      untried = pool;
    }
    MediaCandidate? best;
    var bestEta = double.infinity;
    for (final c in untried) {
      if (book[c.host].inflight >= config.hostInflight) continue;
      // Listed hosts first among the unmeasured: Bilibili picked them
      var eta = book.estimate(c.host, piece.length);
      if (!book[c.host].measured && !c.listed) eta *= 1.5;
      if (eta < bestEta) {
        bestEta = eta;
        best = c;
      }
    }
    return (best, true);
  }

  void _start(_Attempt attempt) {
    final piece = attempt.piece;
    piece.attempts.add(attempt);
    piece.tried.add(attempt.host);
    _inflight++;
    book.inflight++;
    book[attempt.host].inflight++;
    _run(attempt);
  }

  Future<void> _run(_Attempt a) async {
    final piece = a.piece;
    MediaOutcome? outcome;
    var headers = false;
    try {
      final response = await fetcher.fetch(
        a.uri,
        ByteRange(piece.start, piece.end),
        a.cancel,
      );
      var verdict = classifyResponse(
        status: response.status,
        contentRange: response.contentRange,
        expected: ByteRange(piece.start, piece.end),
        expectedTotal: _total,
        redirectedToP2P: response.redirectedToP2P,
      );
      // The file is shorter than the first, blind piece: it ends there
      final range = response.contentRange;
      if (verdict.outcome == .eofClamp &&
          _total == null &&
          range != null &&
          range.total != null &&
          range.start == piece.start &&
          range.end == range.total! - 1) {
        piece.end = range.end;
        verdict = ResponseVerdict(.ok, range.total);
      }
      if (verdict.outcome != .ok) {
        a.cancel.cancel();
        outcome = verdict.outcome;
        return;
      }
      if (a.cancel.isCanceled || piece.done) {
        outcome = .canceled;
        return;
      }
      headers = true;
      contentType ??= response.contentType;
      if (verdict.total case final total? when _total == null) {
        _setEnd(total);
        onTotal?.call(total, contentType);
        if (!_totalKnown.isCompleted) _totalKnown.complete(total);
      }

      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.body) {
        if (a.cancel.isCanceled || piece.done) {
          outcome = a.timedOut ? .truncated : .canceled;
          a.cancel.cancel();
          return;
        }
        final now = book.clock();
        if (a.firstByteAt == 0) {
          a
            ..firstByteAt = now
            ..firstChunk = chunk.length;
        }
        a
          ..lastByteAt = now
          ..received += chunk.length;
        if (a.received > piece.length) {
          outcome = .badRange;
          a.cancel.cancel();
          return;
        }
        builder.add(chunk);
      }
      if (a.cancel.isCanceled || piece.done) {
        outcome = .canceled;
        return;
      }
      if (a.received != piece.length) {
        outcome = .truncated;
        return;
      }
      outcome = .ok;
      piece.data = builder.takeBytes();
      book.recordSuccess(
        a.host,
        ttfbMs: a.firstByteAt - a.startedAt,
        bytes: a.received - a.firstChunk,
        transferMs: a.lastByteAt - a.firstByteAt,
      );
      for (final other in piece.attempts) {
        if (other != a) other.cancel.cancel();
      }
    } catch (_) {
      outcome ??= a.cancel.isCanceled && !a.timedOut
          ? MediaOutcome.canceled
          : headers
          ? MediaOutcome.truncated
          : MediaOutcome.network;
    } finally {
      _finish(a, outcome ?? MediaOutcome.network);
    }
  }

  void _finish(_Attempt a, MediaOutcome outcome) {
    final piece = a.piece;
    piece.attempts.remove(a);
    _inflight--;
    book.inflight--;
    book[a.host].inflight--;
    if (outcome != .ok && outcome != .canceled) {
      book.recordFailure(a.host, outcome);
      if (isFileLevelFailure(outcome)) excluded.add(a.host);
      piece.tries++;
      if (a.fallback && piece.attempts.isEmpty && !piece.done) {
        _fail('fallback failed for ${piece.start}-${piece.end}: $outcome');
        return;
      }
    }
    _signal();
    _pump();
  }
}
