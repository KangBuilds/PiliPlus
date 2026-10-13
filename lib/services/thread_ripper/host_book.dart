// What is known about every CDN host, after host-model.ts of
// Make-Bilibili-Great-Than-Ever-Before (MIT, SukkaW):
//
// - Speed: per host and file, its recent first-byte times, transfer rates and
//   chunk gaps. An edge's speed depends on whether it has the file cached, so
//   a new file starts unmeasured; what a host did on other files only breaks
//   ties.
// - Reliability: cooldowns. A failure while nothing arrives from any host is
//   the viewer's network, and one while the host delivers on another
//   connection is that connection's: neither is held against the host.

import 'dart:math' show max, min;

import 'package:PiliPlus/services/thread_ripper/range.dart';

/// One host's last samples on one file, newest last.
class _Samples {
  final ttfb = <double>[];
  final rate = <double>[];
  final gap = <double>[];

  static const _keep = 8;

  static void add(List<double> samples, double value) {
    samples.add(value);
    if (samples.length > _keep) samples.removeAt(0);
  }

  /// The median: one odd sample does not swing it.
  static double? median(List<double> samples) {
    if (samples.isEmpty) return null;
    final sorted = [...samples]..sort();
    return sorted[sorted.length ~/ 2];
  }
}

/// What is known about one CDN host across files.
class HostStats {
  /// Bytes per millisecond over every file, EWMA; `null` until measured.
  double? rate;

  /// Time to first byte in milliseconds over every file, EWMA.
  double? ttfb;

  int inflight = 0;
  int failures = 0;
  int cooldownUntil = 0;

  /// Bytes it delivered that were used (not lost races).
  int usefulBytes = 0;

  /// When it last delivered a used byte; `0` = never.
  int activeAt = 0;

  /// When any byte last arrived from it; `0` = never.
  int lastBytesAt = 0;

  /// When a request to it last ended: idle long enough, its connections are
  /// closed and the next one pays for a new one.
  int lastUsedAt = 0;

  bool get measured => rate != null;
}

/// Speeds, latencies and cool-downs of every host, learned from what was
/// fetched. Times are milliseconds on [clock]; a file is identified by its
/// path.
class HostBook {
  HostBook({int Function()? clock, this.networkDownMs = 3000})
    : clock = clock ?? _monotonic;

  static final _stopwatch = Stopwatch()..start();
  static int _monotonic() => _stopwatch.elapsedMilliseconds + 1;

  final int Function() clock;
  final _hosts = <String, HostStats>{};

  /// file -> host -> samples; the least recently used file goes first.
  final _files = <String, Map<String, _Samples>>{};
  final _probes = <String, int>{};

  /// Attempts in flight across every job.
  int inflight = 0;

  /// Every byte received, lost races included.
  int fetchedBytes = 0;

  /// Bytes that went into a piece.
  int usefulBytes = 0;

  /// When bytes last arrived from any host, or fetching last started after
  /// a pause: silence counts only while something is in flight.
  int _lastProgressAt = 0;

  /// Hosts with a connection failure since bytes last arrived.
  final _failedSinceProgress = <String>{};

  static const _alpha = 0.3;
  static const _maxFiles = 32;

  /// Transfers shorter than this are mostly round trip: no speed sample.
  static const minSample = 16 * 1024;

  /// Assumed for a host never measured, when no host was.
  static const defaultRate = 768 * 1024 / 1000;
  static const defaultTtfb = 350.0;

  /// Nothing arrived from any host for this long: the network is down.
  final int networkDownMs;

  /// Connection failures on this many hosts with no byte in between: the
  /// network went away, on every host at once.
  static const _hostsFailingTogether = 3;

  /// A host delivered on another connection this recently: it works.
  static const aliveMs = 2000;

  /// Idle for longer, a host's connections are probably closed.
  static const warmMs = 30 * 1000;

  /// Probes per file at most: each duplicates a little.
  static const maxProbesPerFile = 4;

  Iterable<MapEntry<String, HostStats>> get entries => _hosts.entries;

  HostStats operator [](String host) => _hosts.putIfAbsent(host, HostStats.new);

  Map<String, _Samples> _file(String file) {
    final samples = _files.remove(file) ?? {};
    _files[file] = samples;
    while (_files.length > _maxFiles) {
      final oldest = _files.keys.first;
      _files.remove(oldest);
      _probes.remove(oldest);
    }
    return samples;
  }

  _Samples _samples(String host, String file) =>
      _file(file).putIfAbsent(host, _Samples.new);

  /// An attempt starts: after a pause, silence is counted from now.
  void noteStart() {
    if (inflight == 0) _lastProgressAt = clock();
  }

  void noteEnd(String host) => this[host].lastUsedAt = clock();

  void recordBytes(String host, int bytes) {
    final now = clock();
    fetchedBytes += bytes;
    _lastProgressAt = now;
    _failedSinceProgress.clear();
    this[host].lastBytesAt = now;
  }

  void recordUseful(String host, int bytes) {
    usefulBytes += bytes;
    this[host]
      ..usefulBytes += bytes
      ..activeAt = clock();
  }

  void recordTtfb(String host, String file, int ttfbMs) {
    final stats = this[host];
    stats.ttfb = _ewma(stats.ttfb, ttfbMs.toDouble());
    _Samples.add(_samples(host, file).ttfb, ttfbMs.toDouble());
  }

  /// [bytes] arrived over [transferMs] after the first chunk.
  void recordRate(String host, String file, int bytes, int transferMs) {
    if (bytes < minSample) return;
    final rate = bytes / max(transferMs, 1);
    final stats = this[host];
    stats.rate = _ewma(stats.rate, rate);
    _Samples.add(_samples(host, file).rate, rate);
  }

  /// The 90th percentile gap between one request's chunks.
  void recordGap(String host, String file, int gapMs) =>
      _Samples.add(_samples(host, file).gap, gapMs.toDouble());

  /// Waited [waitedMs] without a first byte: a lower bound of the host's
  /// time to first byte on [file], so new pieces go elsewhere.
  void recordWait(String host, String file, int waitedMs) {
    final ttfbs = _samples(host, file).ttfb;
    if (waitedMs > (_Samples.median(ttfbs) ?? 0)) {
      _Samples.add(ttfbs, waitedMs.toDouble());
    }
  }

  void recordSuccess(String host) {
    this[host]
      ..failures = 0
      ..cooldownUntil = 0;
  }

  /// Nothing arrived from any host for a while though something was asked,
  /// or connections to several hosts failed with nothing arriving between.
  bool get networkDown =>
      (_lastProgressAt != 0 && clock() - _lastProgressAt > networkDownMs) ||
      _failedSinceProgress.length >= _hostsFailingTogether;

  static bool _isConnectionFailure(MediaOutcome outcome) =>
      outcome == .network || outcome == .truncated;

  /// Holds [outcome] against [host], unless it says nothing about the host.
  /// `false` when the viewer's network is down: the attempt says nothing
  /// about the piece either.
  bool recordFailure(String host, MediaOutcome outcome) {
    final stats = this[host];
    if (_isConnectionFailure(outcome)) {
      _failedSinceProgress.add(host);
      if (networkDown) {
        // Those that failed before it was clear were not to blame either
        for (final failed in _failedSinceProgress) {
          this[failed]
            ..failures = 0
            ..cooldownUntil = 0;
        }
        return false;
      }
      // One bad connection: the host delivers on its others
      if (clock() - stats.lastBytesAt < aliveMs && stats.lastBytesAt != 0) {
        return true;
      }
    }
    stats.failures++;
    final cooldown = switch (outcome) {
      .refused => 10 * 60 * 1000,
      .throttled => 10 * 1000,
      // Specific to the file: the job excludes the host for it instead
      .missing || .staleObject || .noRange || .redirect => 0,
      _ => min(60 * 1000, 2500 << min(stats.failures - 1, 5)),
    };
    if (cooldown > 0) stats.cooldownUntil = clock() + cooldown;
    return true;
  }

  bool isCoolingDown(String host) => this[host].cooldownUntil > clock();

  /// Measured on [file]: a host fast on another file may not have this one
  /// cached.
  bool isMeasured(String host, String file) =>
      _files[file]?[host]?.rate.isNotEmpty ?? false;

  /// The median over the hosts measured on [file], else over every host,
  /// else what is assumed.
  double typicalRate(String file) =>
      _typical(file, (s) => s.rate) ??
      _medianOf([for (final s in _hosts.values) ?s.rate]) ??
      defaultRate;

  double typicalTtfb(String file) =>
      _typical(file, (s) => s.ttfb) ??
      _medianOf([for (final s in _hosts.values) ?s.ttfb]) ??
      defaultTtfb;

  double? _typical(String file, List<double> Function(_Samples) of) =>
      _medianOf([
        for (final samples in _files[file]?.values ?? const <_Samples>[])
          ?_Samples.median(of(samples)),
      ]);

  /// The usual gap between [host]'s chunks on [file], `null` if unknown.
  double? gap(String host, String file) =>
      _Samples.median(_files[file]?[host]?.gap ?? const []);

  bool mayProbe(String file) => (_probes[file] ?? 0) < maxProbesPerFile;

  void noteProbe(String file) => _probes[file] = (_probes[file] ?? 0) + 1;

  /// [host]'s expected time to first byte (ms) and rate of one request
  /// (bytes per ms) on [file].
  ({double ttfb, double rate}) speedOf(String host, String file) {
    final stats = this[host];
    final own = _files[file]?[host];
    final rate = _Samples.median(own?.rate ?? const []) ?? typicalRate(file);
    var ttfb = _Samples.median(own?.ttfb ?? const []) ?? typicalTtfb(file);
    // A new connection costs about another round of first byte
    if (stats.inflight == 0 && clock() - stats.lastUsedAt > warmMs) ttfb *= 2;
    return (ttfb: ttfb, rate: rate);
  }

  /// Expected milliseconds for [host] to deliver [bytes] of [file], counting
  /// what it is already busy with.
  double estimate(String host, String file, int bytes) {
    final (:ttfb, :rate) = speedOf(host, file);
    // Requests to one host share its bandwidth
    return ttfb + bytes * (this[host].inflight + 1) / rate;
  }

  static double? _medianOf(List<double> values) {
    if (values.isEmpty) return null;
    values.sort();
    return values[values.length ~/ 2];
  }

  static double _ewma(double? old, double sample) =>
      old == null ? sample : old + _alpha * (sample - old);
}
