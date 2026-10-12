import 'dart:math' show max, min;

import 'package:PiliPlus/services/thread_ripper/range.dart';

/// What is known about one CDN host, shared by every file fetched from it.
class HostStats {
  /// Bytes per millisecond, EWMA; `null` until measured.
  double? rate;

  /// Time to first byte in milliseconds, EWMA; `null` until measured.
  double? ttfb;

  int inflight = 0;
  int failures = 0;
  int cooldownUntil = 0;

  bool get measured => rate != null;
}

/// Speeds, latencies and cool-downs of every host, learned from what was
/// fetched. Times are milliseconds on [clock].
class HostBook {
  HostBook({int Function()? clock}) : clock = clock ?? _monotonic;

  static final _stopwatch = Stopwatch()..start();
  static int _monotonic() => _stopwatch.elapsedMilliseconds;

  final int Function() clock;
  final _hosts = <String, HostStats>{};

  /// Attempts in flight across every job.
  int inflight = 0;

  static const _alpha = 0.3;

  /// Transfers shorter than this are mostly round trip: no speed sample.
  static const minSample = 16 * 1024;

  /// Assumed for a host never measured, when no host was.
  static const defaultRate = 1024.0; // ~1 MB/s
  static const defaultTtfb = 400.0;

  HostStats operator [](String host) => _hosts.putIfAbsent(host, HostStats.new);

  void recordSuccess(
    String host, {
    required int ttfbMs,
    required int bytes,
    required int transferMs,
  }) {
    final stats = this[host]
      ..failures = 0
      ..cooldownUntil = 0;
    stats.ttfb = _ewma(stats.ttfb, ttfbMs.toDouble());
    if (bytes >= minSample) {
      stats.rate = _ewma(stats.rate, bytes / max(transferMs, 1));
    }
  }

  void recordFailure(String host, MediaOutcome outcome) {
    final stats = this[host];
    stats.failures++;
    final cooldown = switch (outcome) {
      .refused => 10 * 60 * 1000,
      .throttled => 10 * 1000,
      // Specific to the file: the job excludes the host for it instead
      .missing || .staleObject || .noRange || .redirect => 0,
      _ => min(60 * 1000, 2500 << min(stats.failures - 1, 5)),
    };
    if (cooldown > 0) stats.cooldownUntil = clock() + cooldown;
  }

  /// Waited [waitedMs] without a first byte: a lower bound of the host's
  /// time to first byte, so new pieces go elsewhere.
  void recordWait(String host, int waitedMs) {
    final stats = this[host];
    if (waitedMs > (stats.ttfb ?? 0)) {
      stats.ttfb = _ewma(stats.ttfb, waitedMs.toDouble());
    }
  }

  bool isCoolingDown(String host) => this[host].cooldownUntil > clock();

  double get typicalRate {
    final rates = [
      for (final s in _hosts.values) ?s.rate,
    ]..sort();
    return rates.isEmpty ? defaultRate : rates[rates.length ~/ 2];
  }

  double get typicalTtfb {
    final ttfbs = [
      for (final s in _hosts.values) ?s.ttfb,
    ]..sort();
    return ttfbs.isEmpty ? defaultTtfb : ttfbs[ttfbs.length ~/ 2];
  }

  /// Expected milliseconds for [host] to deliver [bytes], counting what it is
  /// already busy with.
  double estimate(String host, int bytes) {
    final stats = this[host];
    final rate = stats.rate ?? typicalRate;
    final ttfb = stats.ttfb ?? typicalTtfb;
    // Requests to one host share its bandwidth
    return ttfb + bytes * (stats.inflight + 1) / rate;
  }

  static double _ewma(double? old, double sample) =>
      old == null ? sample : old + _alpha * (sample - old);
}
