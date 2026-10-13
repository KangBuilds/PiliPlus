// The serve loop of Make-Bilibili-Great-Than-Ever-Before's thread-ripper
// (MIT, SukkaW), reduced for a native player that reads one open-ended range:
//
// - Pieces: the range is cut into pieces of about a second of transfer each,
//   fetched a window ahead of what the player reads. Bytes go into a piece's
//   buffer at its frontier as they arrive, and the piece the player waits on
//   is handed out as it fills.
// - Owners: a piece goes to the host expected to finish it first.
// - Races: the piece the player waits on first starts on two hosts; any piece
//   with no first byte or stalled gets a racer on another host. Once racers
//   both receive, the one behind goes, unless it is still measuring a host
//   never measured before.
// - Endgame: with slots free and nothing waiting, the slowest piece's tail is
//   split off to another host, and idle slots measure unmeasured hosts.
// - Failure: the rest of a piece is retried on other hosts, then on the
//   player's own URL; after that the job fails.

import 'dart:async';
import 'dart:math' show max, min;
import 'dart:typed_data';

import 'package:PiliPlus/services/thread_ripper/candidates.dart';
import 'package:PiliPlus/services/thread_ripper/fetcher.dart';
import 'package:PiliPlus/services/thread_ripper/host_book.dart';
import 'package:PiliPlus/services/thread_ripper/range.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

const _kib = 1024;
const _mib = 1024 * _kib;

class RipperConfig {
  const RipperConfig({
    this.firstPiece = 256 * _kib,
    this.minPiece = 512 * _kib,
    this.maxPiece = 4 * _mib,
    this.pieceMs = 1000,
    this.pieceTtfbs = 4,
    this.maxPiecesAhead = 8,
    this.maxBytesAhead = 16 * _mib,
    this.jobInflight = 8,
    this.globalInflight = 24,
    this.urgentReserve = 2,
    this.hostInflight = 4,
    this.maxRacers = 3,
    this.maxTries = 6,
    this.headTtfbMs = 700,
    this.ttfbMs = 1500,
    this.headStallMs = 800,
    this.stallMs = 1500,
    this.giveUpMs = 8000,
    this.stuckMs = 30000,
    this.laggardBytes = 64 * _kib,
    this.probeBytes = 64 * _kib,
    this.stealMin = 192 * _kib,
    this.ownerBand = 1.25,
    this.smallPiece = 256 * _kib,
    this.tickMs = 100,
  });

  /// The first piece of a job whose file size is unknown: small, it is about
  /// latency.
  final int firstPiece;
  final int minPiece;
  final int maxPiece;

  /// A piece is about this long a transfer at the typical host rate...
  final int pieceMs;

  /// ...and at least this many times the typical time to first byte.
  final int pieceTtfbs;
  final int maxPiecesAhead;
  final int maxBytesAhead;
  final int jobInflight;
  final int globalInflight;

  /// Slots above [jobInflight] only the piece the player waits on may take,
  /// to be rescued while later pieces hold every slot. [globalInflight]
  /// stays a hard limit.
  final int urgentReserve;
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

  /// A piece that made no progress for this long, every host and the
  /// player's own URL tried: the job fails.
  final int stuckMs;

  /// A racer this far behind the leader only duplicates bytes: it goes.
  final int laggardBytes;

  /// A racer on a host never measured runs at least this far, enough to
  /// measure the host.
  final int probeBytes;

  /// Neither half of a split piece is smaller.
  final int stealMin;

  /// A piece goes on its own only to a host expected to finish it within
  /// this factor of the best one: on a slower host the player would wait
  /// for that piece.
  final double ownerBand;

  /// A piece this small is about latency: it goes to the host expected to
  /// finish it first, not the least busy.
  final int smallPiece;
  final int tickMs;
}

class RipperJobFailed implements Exception {
  const RipperJobFailed(this.message);

  final String message;

  @override
  String toString() => 'RipperJobFailed: $message';
}

class _Piece {
  _Piece(this.start, this.end)
    : buffer = Uint8List(end - start + 1),
      frontier = start,
      handedOut = start;

  final int start;

  /// Inclusive. Moves in when the tail is split off.
  int end;

  /// Sized for the piece before any split.
  final Uint8List buffer;

  /// Everything below it is written. Only ever moves forward.
  int frontier;

  /// Everything below it went to the player.
  int handedOut;

  final attempts = <_Attempt>{};

  /// Hosts tried for it, so a retry goes elsewhere.
  final tried = <String>{};
  int tries = 0;
  bool fallbackTried = false;

  /// After a failure while the network was down: not before then.
  int retryAt = 0;

  /// When it last received a byte, or was first started; `0` = not yet.
  int lastProgressAt = 0;

  /// How each host (and the player's own URL) last failed it.
  final failures = <String, MediaOutcome>{};

  int get length => end - start + 1;
  int get remaining => end - frontier + 1;
  bool get done => frontier > end;
}

class _Attempt {
  _Attempt(
    this.piece,
    this.uri,
    this.host,
    this.startedAt, {
    this.fallback = false,
    this.probe = false,
  }) : from = piece.frontier,
       to = piece.end,
       pos = piece.frontier;

  final _Piece piece;
  final Uri uri;
  final String host;
  final int startedAt;
  final bool fallback;

  /// On a host never measured: not cut as a laggard before `probeBytes`.
  final bool probe;

  /// The range it asked for.
  final int from;
  final int to;

  /// Absolute offset of the next byte it receives.
  int pos;
  final cancel = CancelSignal();
  int firstByteAt = 0;
  int lastByteAt = 0;
  int received = 0;

  /// Arrives with the headers: left out of speed samples.
  int firstChunk = 0;

  /// Given up by us, which is a failure of its host, unlike a lost race.
  bool timedOut = false;

  /// Gaps between its chunks, ms.
  final gaps = <int>[];

  /// Bytes it wrote into the piece.
  int useful = 0;

  bool get receiving => firstByteAt != 0;

  /// Bytes per millisecond since its first byte; `null` until it says much.
  double? rate(int now) {
    final bytes = received - firstChunk;
    if (bytes < HostBook.minSample || now <= firstByteAt) return null;
    return bytes / (now - firstByteAt);
  }
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
    String? file,
    int? total,
    this.racing = _always,
    this.config = const RipperConfig(),
    this.onTotal,
  }) : file = file ?? fallback.path,
       _total = total {
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

  /// Identifies the file to the host book: speeds are per file.
  final String file;

  /// Whether duplicates may be started (Wi-Fi).
  final bool Function() racing;
  final RipperConfig config;
  final void Function(int total, String? contentType)? onTotal;

  int? _total;
  int? _end;
  String? contentType;
  int _nextOffset = -1;
  int _inflight = 0;
  final _window = <_Piece>[];
  Object? _error;
  bool _closed = false;
  bool _handedOut = false;
  Timer? _ticker;
  Completer<void>? _changed;
  final _totalKnown = Completer<int>();

  int? get total => _total;

  @visibleForTesting
  bool get ticking => _ticker?.isActive ?? false;

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

  /// The next bytes in order, as soon as any are there; `null` once the
  /// range is complete.
  Future<Uint8List?> next() async {
    while (true) {
      if (_error case final error?) throw error;
      if (_closed) throw const RipperJobFailed('canceled');
      if (_window.isNotEmpty) {
        final head = _window.first;
        if (head.handedOut < head.frontier) {
          final bytes = Uint8List.sublistView(
            head.buffer,
            head.handedOut - head.start,
            head.frontier - head.start,
          );
          head.handedOut = head.frontier;
          if (head.done) _window.removeAt(0);
          _handedOut = true;
          _pump();
          return bytes;
        }
      }
      if (_end != null && _window.isEmpty && _nextOffset > _end!) {
        // Complete: nothing left to schedule
        _ticker?.cancel();
        return null;
      }
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

  int get _pieceSize {
    // Far from the CDN every request waits long for its first byte: a piece
    // must be long enough that the wait stays a small part of it
    final ms = max(
      config.pieceMs,
      book.typicalTtfb(file) * config.pieceTtfbs,
    );
    return (book.typicalRate(file) * ms).round().clamp(
      config.minPiece,
      config.maxPiece,
    );
  }

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
      final piece = _Piece(
        _nextOffset,
        min(_nextOffset + _pieceSize - 1, end),
      );
      _window.add(piece);
      ahead += piece.length;
      _nextOffset = piece.end + 1;
    }
  }

  bool get _slotFree => _hasSlot();

  bool _hasSlot({bool urgent = false}) =>
      _inflight < config.jobInflight + (urgent ? config.urgentReserve : 0) &&
      book.inflight < config.globalInflight;

  void _pump() {
    if (_closed) return;
    _plan();
    final now = book.clock();

    _giveUpSilent(now);
    _cutLaggards();
    // Give the head's rescue a free slot before fetching later pieces.
    if (racing()) _race(now);

    // Owners: every piece without an attempt gets one, in order
    var waiting = false;
    for (final piece in _window) {
      if (piece.done || piece.attempts.isNotEmpty) continue;
      if (piece.retryAt > now) {
        waiting = true;
        continue;
      }
      if (!_slotFree) {
        waiting = true;
        break;
      }
      if (!_launch(piece)) return;
      if (identical(piece, _window.first) && racing()) _race(now);
      if (piece.attempts.isEmpty) waiting = true;
    }

    if (!waiting && _slotFree) {
      _splitTail(now);
      if (racing()) _probe();
    }
  }

  void _giveUpSilent(int now) {
    for (final piece in _window) {
      for (final a in piece.attempts) {
        final silentFor = now - (a.receiving ? a.lastByteAt : a.startedAt);
        if (silentFor > config.giveUpMs && !a.timedOut) {
          a
            ..timedOut = true
            ..cancel.cancel();
        }
      }
    }
  }

  /// Racers both receiving: the one behind only duplicates bytes.
  void _cutLaggards() {
    for (final piece in _window) {
      if (piece.done || piece.attempts.length < 2) continue;
      var lead = 0;
      for (final a in piece.attempts) {
        if (a.receiving && a.pos > lead) lead = a.pos;
      }
      for (final a in piece.attempts) {
        if (!a.receiving || a.cancel.isCanceled) continue;
        if (a.probe && a.received < config.probeBytes) continue;
        if (lead - a.pos > config.laggardBytes) a.cancel.cancel();
      }
    }
  }

  void _race(int now) {
    var isHead = true;
    for (final piece in _window) {
      final head = isHead;
      isHead = false;
      if (piece.done || piece.attempts.isEmpty) continue;
      if (piece.attempts.length >= config.maxRacers) continue;
      if (piece.attempts.any((a) => a.fallback)) continue;
      if (!_hasSlot(urgent: head)) {
        // Only the head may dip into the reserve: the rest wait their turn
        if (head) continue;
        break;
      }
      if (_needsRacer(piece, head, now)) {
        for (final a in piece.attempts) {
          if (!a.receiving) book.recordWait(a.host, file, now - a.startedAt);
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
      (book.typicalTtfb(file) * 3).round(),
    );
    final stallLimit = head ? config.headStallMs : config.stallMs;
    return piece.attempts.every((a) {
      if (!a.receiving) return now - a.startedAt > ttfbLimit;
      // A host whose chunks usually come far apart is not stalled yet
      final gap = book.gap(a.host, file) ?? 0;
      return now - a.lastByteAt > max(stallLimit, (gap * 2).round());
    });
  }

  /// The piece expected to finish last gives its tail to a host expected to
  /// finish that part sooner.
  void _splitTail(int now) {
    final end = _end;
    if (end == null) return;
    _Piece? slowest;
    _Attempt? owner;
    double slowestEta = 0;
    for (final piece in _window) {
      if (piece.done || piece.attempts.length != 1) continue;
      final a = piece.attempts.first;
      if (a.fallback || a.cancel.isCanceled) continue;
      final rate = a.rate(now);
      if (rate == null || piece.remaining < 2 * config.stealMin) continue;
      final eta = piece.remaining / rate;
      if (eta > slowestEta) {
        slowestEta = eta;
        slowest = piece;
        owner = a;
      }
    }
    if (slowest == null || owner == null) return;

    final (candidate, _) = _choose(slowest, bytes: slowest.remaining ~/ 2);
    if (candidate == null) return;
    final r1 = owner.rate(now)!;
    final (ttfb: ttfb2, rate: r2) = _speedWithLoad(candidate.host, now);
    // Both halves finish together: k / r1 = ttfb2 + (remaining - k) / r2
    final remaining = slowest.remaining;
    final k = (r1 * (ttfb2 + remaining / r2) / (1 + r1 / r2)).round();
    if (k < config.stealMin || remaining - k < config.stealMin) return;
    // Worth it only when the new host finishes its part before the owner
    // would have finished the whole
    if (ttfb2 + (remaining - k) / r2 >= slowestEta) return;

    final at = slowest.frontier + k;
    final tail = _Piece(at, slowest.end);
    slowest.end = at - 1;
    _window.insert(_window.indexOf(slowest) + 1, tail);
    _start(_Attempt(tail, candidate.uri, candidate.host, book.clock()));
  }

  /// An idle slot measures a host never measured, on the piece with the most
  /// left: its bytes count if it turns out faster.
  void _probe() {
    if (_end == null || !book.mayProbe(file)) return;
    if (_window.any((p) => p.attempts.any((a) => a.probe))) return;
    _Piece? target;
    // Never the piece the player waits on, nor one already raced: a probe
    // only duplicates bytes of an owner that is on its own
    for (final piece in _window.skip(1)) {
      if (piece.done ||
          piece.attempts.length != 1 ||
          piece.attempts.any((a) => a.fallback) ||
          piece.remaining < 2 * config.probeBytes) {
        continue;
      }
      if (target == null || piece.remaining > target.remaining) {
        target = piece;
      }
    }
    if (target == null) return;
    final busy = {for (final a in target.attempts) a.host};
    for (final c in candidates) {
      final stats = book[c.host];
      if (book.isMeasured(c.host, file) ||
          busy.contains(c.host) ||
          excluded.contains(c.host) ||
          book.isCoolingDown(c.host) ||
          stats.inflight >= config.hostInflight) {
        continue;
      }
      book.noteProbe(file);
      _start(_Attempt(target, c.uri, c.host, book.clock(), probe: true));
      return;
    }
  }

  /// Starts an attempt on [piece]; `false` when the job failed meanwhile.
  bool _launch(_Piece piece, {bool racer = false}) {
    final (candidate, waitable) = _choose(piece, racer: racer);
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
    // Hosts that only cool down come back: a new round once they do, until
    // the piece has been stuck too long
    final now = book.clock();
    if (candidates.any((c) => !excluded.contains(c.host)) &&
        now - piece.lastProgressAt < config.stuckMs) {
      piece
        ..tries = 0
        ..fallbackTried = false
        ..retryAt = now + 500;
      return true;
    }
    _fail(
      'no host could deliver ${piece.start}-${piece.end} of $total: '
      '${piece.failures.entries.map((e) => '${e.key} ${e.value.name}').join(', ')}',
    );
    return false;
  }

  /// What [host]'s requests receive now, together and per request; the
  /// CDN throttles each request, so more of them add up.
  ({double ttfb, double rate}) _speedWithLoad(String host, int now) {
    final speed = book.speedOf(host, file);
    var receiving = 0;
    var together = 0.0;
    for (final piece in _window) {
      for (final a in piece.attempts) {
        if (a.host != host || a.cancel.isCanceled) continue;
        if (a.rate(now) case final rate?) {
          receiving++;
          together += rate;
        }
      }
    }
    if (receiving == 0) return speed;
    return (ttfb: speed.ttfb, rate: min(speed.rate, together / receiving));
  }

  double _eta(String host, int bytes, int now) {
    final (:ttfb, :rate) = _speedWithLoad(host, now);
    return ttfb + bytes / rate;
  }

  /// The hosts a piece of [bytes] may go to on its own: the measured ones
  /// expected to finish it within `ownerBand` of the best. `null` while none
  /// is measured: any host may.
  Set<String>? _owners(int bytes, int now) {
    final etas = <String, double>{};
    for (final c in candidates) {
      if (excluded.contains(c.host) ||
          book.isCoolingDown(c.host) ||
          !book.isMeasured(c.host, file)) {
        continue;
      }
      etas[c.host] = _eta(c.host, bytes, now);
    }
    if (etas.isEmpty) return null;
    final best = etas.values.reduce(min);
    return {
      for (final MapEntry(key: host, value: eta) in etas.entries)
        if (eta <= best * config.ownerBand) host,
    };
  }

  /// Where [bytes] of [piece] (the rest of it by default) go, and whether,
  /// when nowhere, a host may free up for it.
  ///
  /// An owner only goes to a host that may carry the piece alone
  /// ([_owners]): the least busy of them, or the fastest for a small piece.
  /// A racer goes to the fastest measured host; to [explore], or while none
  /// is measured, to one never measured, the listed addresses first.
  (MediaCandidate?, bool) _choose(
    _Piece piece, {
    int? bytes,
    bool racer = false,
    bool explore = false,
  }) {
    if (piece.tries >= config.maxTries) return (null, false);
    bytes ??= piece.remaining;
    final now = book.clock();
    final owners = racer ? null : _owners(bytes, now);
    final busy = {for (final a in piece.attempts) a.host};
    final pool = [
      for (final c in candidates)
        if (!excluded.contains(c.host) &&
            !busy.contains(c.host) &&
            !book.isCoolingDown(c.host) &&
            (owners == null || owners.contains(c.host)))
          c,
    ];
    if (pool.isEmpty) return (null, false);
    var untried = pool.where((c) => !piece.tried.contains(c.host)).toList();
    if (untried.isEmpty) {
      // Every host was tried: a new round
      piece.tried.removeWhere((host) => !busy.contains(host));
      untried = pool;
    }
    final options = [
      for (final c in untried)
        if (book[c.host].inflight < config.hostInflight) c,
    ];
    if (options.isEmpty) return (null, true);

    final unmeasured = [
      for (final c in options)
        if (!book.isMeasured(c.host, file)) c,
    ];
    final MediaCandidate chosen;
    if (unmeasured.length == options.length ||
        (racer && explore && unmeasured.isNotEmpty)) {
      chosen = _leastBusy(_preferred(unmeasured), bytes, now);
    } else {
      final measured = [
        for (final c in options)
          if (book.isMeasured(c.host, file)) c,
      ];
      chosen = racer || bytes < config.smallPiece || _window.length == 1
          ? _fastest(measured, bytes, now)
          : _leastBusy(measured, bytes, now);
    }
    return (chosen, true);
  }

  /// Among unmeasured hosts: the addresses Bilibili listed for the file
  /// first, the signatures moved elsewhere after.
  List<MediaCandidate> _preferred(List<MediaCandidate> options) {
    final listed = [
      for (final c in options)
        if (c.listed) c,
    ];
    return listed.isNotEmpty ? listed : options;
  }

  MediaCandidate _leastBusy(List<MediaCandidate> options, int bytes, int now) =>
      options.reduce((best, c) {
        final load = book[c.host].inflight;
        final bestLoad = book[best.host].inflight;
        if (load != bestLoad) return load < bestLoad ? c : best;
        return _eta(c.host, bytes, now) < _eta(best.host, bytes, now)
            ? c
            : best;
      });

  MediaCandidate _fastest(List<MediaCandidate> options, int bytes, int now) =>
      options.reduce(
        (best, c) =>
            _eta(c.host, bytes, now) < _eta(best.host, bytes, now) ? c : best,
      );

  void _start(_Attempt attempt) {
    final piece = attempt.piece;
    piece.attempts.add(attempt);
    piece.tried.add(attempt.host);
    if (piece.lastProgressAt == 0) piece.lastProgressAt = book.clock();
    book.noteStart();
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
      final expected = ByteRange(a.from, a.to);
      final response = await fetcher.fetch(a.uri, expected, a.cancel);
      var verdict = classifyResponse(
        status: response.status,
        contentRange: response.contentRange,
        expected: expected,
        expectedTotal: _total,
        redirectedToP2P: response.redirectedToP2P,
      );
      // The file is shorter than the first, blind piece: it ends there
      final range = response.contentRange;
      if (verdict.outcome == .eofClamp &&
          _total == null &&
          range != null &&
          range.total != null &&
          range.start == a.from &&
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

      await for (final chunk in response.body) {
        if (a.cancel.isCanceled) {
          outcome = a.timedOut ? .truncated : .canceled;
          return;
        }
        if (_write(a, chunk) case final result?) {
          outcome = result;
          a.cancel.cancel();
          return;
        }
      }
      if (a.cancel.isCanceled) {
        outcome = a.timedOut ? .truncated : .canceled;
        return;
      }
      // Ended before what it asked for, and before the piece was done
      outcome = a.pos > a.to || piece.done ? .ok : .truncated;
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

  /// Writes what [chunk] adds past the piece's frontier. `null` to keep
  /// reading, else how the attempt ends.
  MediaOutcome? _write(_Attempt a, List<int> chunk) {
    final piece = a.piece;
    final now = book.clock();
    if (!a.receiving) {
      a
        ..firstByteAt = now
        ..firstChunk = chunk.length;
      book.recordTtfb(a.host, file, now - a.startedAt);
    } else {
      a.gaps.add(now - a.lastByteAt);
    }
    final chunkStart = a.pos;
    a
      ..lastByteAt = now
      ..received += chunk.length
      ..pos += chunk.length;
    book.recordBytes(a.host, chunk.length);
    if (a.pos - 1 > a.to) return .badRange;

    final from = max(chunkStart, piece.frontier);
    final until = min(a.pos - 1, piece.end);
    if (from <= until) {
      piece.buffer.setRange(
        from - piece.start,
        until - piece.start + 1,
        chunk,
        from - chunkStart,
      );
      piece.frontier = until + 1;
      book.recordUseful(a.host, until - from + 1);
      a.useful += until - from + 1;
      piece.lastProgressAt = now;
      if (identical(piece, _window.firstOrNull)) _signal();
    }
    if (piece.done) {
      for (final other in piece.attempts) {
        if (other != a) other.cancel.cancel();
      }
      return .ok;
    }
    return null;
  }

  void _finish(_Attempt a, MediaOutcome outcome) {
    final piece = a.piece;
    piece.attempts.remove(a);
    _inflight--;
    book.inflight--;
    book[a.host].inflight--;
    book.noteEnd(a.host);
    // Lost races and split-off tails measure their host as well
    if (a.receiving) {
      book.recordRate(
        a.host,
        file,
        a.received - a.firstChunk,
        a.lastByteAt - a.firstByteAt,
      );
      if (a.gaps.length >= 4) {
        final gaps = [...a.gaps]..sort();
        book.recordGap(a.host, file, gaps[(gaps.length * 9) ~/ 10]);
      }
    }
    if (outcome == .ok) {
      book.recordSuccess(a.host);
    } else if (outcome != .canceled) {
      if (!book.recordFailure(a.host, outcome)) {
        // The viewer's network is down: nothing to learn about the host or
        // the piece. Try again shortly, the player's own URL included
        piece.retryAt = book.clock() + 500;
        if (a.fallback) piece.fallbackTried = false;
      } else {
        piece.failures[a.fallback ? 'own URL' : a.host] = outcome;
        if (isFileLevelFailure(outcome)) excluded.add(a.host);
        if (a.useful > 0) {
          // It moved the piece on: a connection failed, not the piece, and
          // the rest resumes where it stopped
          piece.tries = 0;
          if (a.fallback) piece.fallbackTried = false;
        } else {
          piece.tries++;
        }
      }
    }
    _signal();
    _pump();
  }
}
