import 'dart:async';
import 'dart:io';
import 'dart:math' show min;

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

  HttpServer? _server;
  Future<HttpServer>? _starting;
  int? _port;
  int _seq = 0;
  final _sources = <String, _Source>{};
  final _alternatives = <String, List<String>>{};
  bool _wifi = true;
  StreamSubscription<List<ConnectivityResult>>? _connectivity;

  bool get enabled => Pref.threadRipper;

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
    _sources[id] = _Source(uri, candidates);
    while (_sources.length > _maxSources) {
      _sources.remove(_sources.keys.first);
    }
    return 'http://${InternetAddress.loopbackIPv4.address}:${server.port}/m/$id';
  }

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

      job = RipperJob(
        candidates: source.candidates,
        fallback: source.fallback,
        start: range.start,
        requestedEnd: range.end,
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

      final int total;
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

      final end = min(range.end ?? total - 1, total - 1);
      response
        ..statusCode = rangeHeader == null
            ? HttpStatus.ok
            : HttpStatus.partialContent
        ..contentLength = end - range.start + 1
        ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..headers.set(
          HttpHeaders.contentTypeHeader,
          source.contentType ?? job.contentType ?? 'video/mp4',
        );
      if (rangeHeader != null) {
        response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes ${range.start}-$end/$total',
        );
      }
      if (request.method == 'HEAD') {
        job.cancel();
        return;
      }

      // mpv closed the connection (a seek, a new video): stop fetching
      final runningJob = job;
      response.done.whenComplete(runningJob.cancel).ignore();
      while (true) {
        final chunk = await job.next();
        if (chunk == null) break;
        response.add(chunk);
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

  void _redirect(HttpResponse response, Uri location) {
    response
      ..statusCode = HttpStatus.found
      ..headers.set(HttpHeaders.locationHeader, location.toString());
  }
}
