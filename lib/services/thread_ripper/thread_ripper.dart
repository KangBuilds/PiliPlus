import 'dart:async';
import 'dart:io';
import 'dart:math' show min;
import 'dart:typed_data';

import 'package:PiliPlus/services/thread_ripper/candidates.dart';
import 'package:PiliPlus/services/thread_ripper/fetcher.dart';
import 'package:PiliPlus/services/thread_ripper/host_book.dart';
import 'package:PiliPlus/services/thread_ripper/job.dart';
import 'package:PiliPlus/services/thread_ripper/range.dart';
import 'package:PiliPlus/utils/connectivity_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

final threadRipper = ThreadRipper();

/// One file the player was handed a proxy URL for.
class _Source {
  _Source(this.fallback, this.candidates);

  final Uri fallback;
  final List<MediaCandidate> candidates;
  final excluded = <String>{};
  int? total;
  String? contentType;

  /// A job of it failed: the player's retries go straight to [fallback] until
  /// then.
  int directUntil = 0;

  /// The file's first bytes, fetched as soon as the URL is handed out: mpv
  /// reads them (the init segment and the index) before anything else.
  /// `null` when the warm-up failed.
  Future<Uint8List?>? head;
}

/// What the proxy does, for the playback info panel.
class RipperStats {
  const RipperStats({
    required this.servedRate,
    required this.fetchedBytes,
    required this.usefulBytes,
    required this.hosts,
  });

  /// Bytes per second handed to the player recently.
  final double servedRate;

  /// Every byte received, lost races included.
  final int fetchedBytes;

  /// Bytes that went to the player.
  final int usefulBytes;

  /// Hosts that delivered recently, with their speed in bytes per second,
  /// fastest first.
  final List<(String, double)> hosts;

  /// Received but not used, as a fraction of what was used.
  double get overhead => usefulBytes == 0 ? 0 : fetchedBytes / usefulBytes - 1;
}

/// A loopback HTTP proxy between mpv and Bilibili's CDNs: each range mpv
/// reads is fetched in pieces from many hosts at once ([RipperJob]).
///
/// Only on Wi-Fi: elsewhere, and whenever it cannot help, mpv is sent to the
/// URL it would have used.
class ThreadRipper {
  ThreadRipper({
    RangeFetcher? fetcher,
    HostBook? book,
    this.config = const RipperConfig(),
    this.wifiOnly = true,
  }) : fetcher = fetcher ?? HttpRangeFetcher(),
       book = book ?? HostBook();

  final RangeFetcher fetcher;
  final HostBook book;
  final RipperConfig config;
  final bool wifiOnly;

  /// A request gets no validated response from any host by then: mpv is sent
  /// to its own URL.
  static const commitTimeout = Duration(seconds: 5);
  static const _directAfterFailure = 30 * 1000;
  static const _maxSources = 16;
  static const _maxAlternatives = 64;
  static const _rateWindowMs = 2000;
  static const _activeHostMs = 5000;

  HttpServer? _server;
  Future<HttpServer>? _starting;
  int? _port;
  int _seq = 0;
  final _sources = <String, _Source>{};
  final _alternatives = <String, List<String>>{};
  bool _wifi = true;

  /// (time, bytes) handed to the player within the last `_rateWindowMs`.
  final _served = <(int, int)>[];
  StreamSubscription<List<ConnectivityResult>>? _connectivity;

  bool get enabled => Pref.threadRipper;

  /// Whether [url] is one this proxy handed out.
  bool isProxyUrl(String url) =>
      _port != null &&
      url.startsWith(
        'http://${InternetAddress.loopbackIPv4.address}:$_port/m/',
      );

  RipperStats get stats {
    final now = book.clock();
    _served.removeWhere((e) => now - e.$1 > _rateWindowMs);
    var served = 0;
    for (final (_, bytes) in _served) {
      served += bytes;
    }
    final hosts = [
      for (final MapEntry(key: host, value: stats) in book.entries)
        if (now - stats.activeAt <= _activeHostMs && stats.activeAt != 0)
          (host, (stats.rate ?? 0) * 1000),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    return RipperStats(
      servedRate: served * 1000 / _rateWindowMs,
      fetchedBytes: book.fetchedBytes,
      usefulBytes: book.usefulBytes,
      hosts: hosts,
    );
  }

  /// The playurl's other addresses of the file [selected] was picked from.
  void rememberAlternatives(String selected, Iterable<String> urls) {
    _alternatives
      ..remove(selected)
      ..[selected] = urls.toList(growable: false);
    while (_alternatives.length > _maxAlternatives) {
      _alternatives.remove(_alternatives.keys.first);
    }
  }

  /// A URL for mpv: through the proxy when enabled, on Wi-Fi and worth it;
  /// [url] itself otherwise.
  Future<String> wrap(String url) async {
    if (!enabled) return url;
    if (wifiOnly && !await ConnectivityUtils.isWiFi) return url;
    return wrapNow(url);
  }

  @visibleForTesting
  Future<String> wrapNow(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.path.contains('/upgcxcode/')) return url;
    final candidates = mediaCandidates([url, ...?_alternatives[url]]);
    if (candidates.length < 2) return url;
    final HttpServer server;
    try {
      server = await _ensureServer();
    } catch (e) {
      if (kDebugMode) debugPrint('thread ripper: $e');
      return url;
    }
    final id = (++_seq).toString();
    final source = _sources[id] = _Source(uri, candidates);
    source.head = _warmUp(source);
    while (_sources.length > _maxSources) {
      _sources.remove(_sources.keys.first);
    }
    return 'http://${InternetAddress.loopbackIPv4.address}:${server.port}/m/$id';
  }

  Future<Uint8List?> _warmUp(_Source source) async {
    final job = _job(source, 0, config.firstPiece - 1);
    try {
      await job.begin().timeout(commitTimeout);
      final head = BytesBuilder(copy: false);
      for (var c = await job.next(); c != null; c = await job.next()) {
        head.add(c);
      }
      return head.takeBytes();
    } catch (_) {
      job.cancel();
      return null;
    }
  }

  RipperJob _job(_Source source, int start, int? end) => RipperJob(
    candidates: source.candidates,
    fallback: source.fallback,
    start: start,
    requestedEnd: end,
    total: source.total,
    book: book,
    fetcher: fetcher,
    excluded: source.excluded,
    racing: () => !wifiOnly || _wifi,
    config: config,
    onTotal: (total, contentType) {
      source
        ..total = total
        ..contentType ??= contentType;
    },
  );

  Future<HttpServer> _ensureServer() {
    if (_server case final server?) return Future.value(server);
    return _starting ??= _bind().whenComplete(() => _starting = null);
  }

  Future<HttpServer> _bind() async {
    HttpServer server;
    try {
      // The same port again: URLs mpv holds stay valid after a restart
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, _port ?? 0);
    } on SocketException {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    }
    server
      ..idleTimeout = const Duration(seconds: 30)
      ..autoCompress = false;
    _port = server.port;
    _server = server;
    if (wifiOnly) {
      _connectivity ??= Connectivity().onConnectivityChanged.listen(
        (results) => _wifi = results.contains(ConnectivityResult.wifi),
      );
    }
    void restart([_]) {
      // iOS may take the socket away while the app is suspended
      if (identical(_server, server)) _server = null;
      _ensureServer().ignore();
    }

    server.listen(_handle, onError: restart, onDone: restart);
    return server;
  }

  @visibleForTesting
  Future<void> close() async {
    await _connectivity?.cancel();
    _connectivity = null;
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    RipperJob? job;
    try {
      final segments = request.uri.pathSegments;
      final source = segments.length == 2 && segments[0] == 'm'
          ? _sources[segments[1]]
          : null;
      if (source == null) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      if (request.method != 'GET' && request.method != 'HEAD') {
        response.statusCode = HttpStatus.methodNotAllowed;
        return;
      }
      final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
      final range = rangeHeader == null
          ? (start: 0, end: null)
          : parseRangeHeader(rangeHeader);
      if (range == null ||
          (wifiOnly && !_wifi) ||
          source.directUntil > book.clock()) {
        _redirect(response, source.fallback);
        return;
      }

      // The first bytes come from the warm-up, the rest from a job
      Uint8List? prefix;
      final head = source.head == null || range.start >= config.firstPiece
          ? null
          : await source.head!.timeout(commitTimeout, onTimeout: () => null);
      final int total;
      if (head != null && source.total != null && range.start < head.length) {
        total = source.total!;
        final end = min(range.end ?? total - 1, total - 1);
        prefix = Uint8List.sublistView(
          head,
          range.start,
          min(head.length, end + 1),
        );
        if (end >= head.length) {
          job = _job(source, head.length, end)..begin().ignore();
        }
      } else {
        job = _job(source, range.start, range.end);
        try {
          total = await job.begin().timeout(commitTimeout);
        } catch (_) {
          job.cancel();
          if (source.total case final total? when range.start >= total) {
            response
              ..statusCode = HttpStatus.requestedRangeNotSatisfiable
              ..headers.set(HttpHeaders.contentRangeHeader, 'bytes */$total');
            return;
          }
          _redirect(response, source.fallback);
          return;
        }
      }

      final end = min(range.end ?? total - 1, total - 1);
      response
        ..statusCode = rangeHeader == null
            ? HttpStatus.ok
            : HttpStatus.partialContent
        ..contentLength = end - range.start + 1
        ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..headers.set(
          HttpHeaders.contentTypeHeader,
          source.contentType ?? job?.contentType ?? 'video/mp4',
        );
      if (rangeHeader != null) {
        response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes ${range.start}-$end/$total',
        );
      }
      if (request.method == 'HEAD') {
        job?.cancel();
        return;
      }

      if (prefix != null) {
        _serve(response, prefix);
        await response.flush();
      }
      if (job == null) return;

      // mpv closed the connection (a seek, a new video): stop fetching
      final runningJob = job;
      response.done.whenComplete(runningJob.cancel).ignore();
      for (
        var c = await runningJob.next();
        c != null;
        c = await runningJob.next()
      ) {
        _serve(response, c);
        await response.flush();
      }
    } catch (e) {
      job?.cancel();
      if (e is RipperJobFailed && e.message != 'canceled') {
        final segments = request.uri.pathSegments;
        if (segments.length == 2) {
          _sources[segments[1]]?.directUntil =
              book.clock() + _directAfterFailure;
        }
        if (kDebugMode) debugPrint('thread ripper: $e');
      }
      // Committed: closing short of Content-Length drops the connection, mpv
      // sees the body end early and opens the range again
    } finally {
      try {
        await response.close();
      } catch (_) {}
    }
  }

  void _serve(HttpResponse response, Uint8List bytes) {
    response.add(bytes);
    _served.add((book.clock(), bytes.length));
  }

  void _redirect(HttpResponse response, Uri location) {
    response
      ..statusCode = HttpStatus.found
      ..headers.set(HttpHeaders.locationHeader, location.toString());
  }
}
