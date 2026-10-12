import 'dart:async';
import 'dart:io';

import 'package:PiliPlus/http/browser_ua.dart';
import 'package:PiliPlus/http/constants.dart';
import 'package:PiliPlus/services/thread_ripper/candidates.dart';
import 'package:PiliPlus/services/thread_ripper/range.dart';

/// Cancels one attempt: aborts its request, or its body mid-way.
class CancelSignal {
  bool _canceled = false;
  final _callbacks = <void Function()>[];

  bool get isCanceled => _canceled;

  void onCancel(void Function() callback) {
    if (_canceled) {
      callback();
    } else {
      _callbacks.add(callback);
    }
  }

  void cancel() {
    if (_canceled) return;
    _canceled = true;
    for (final callback in _callbacks) {
      callback();
    }
    _callbacks.clear();
  }
}

class RangeResponse {
  const RangeResponse({
    required this.status,
    required this.contentRange,
    required this.body,
    this.contentType,
    this.redirectedToP2P = false,
  });

  final int status;
  final ContentRange? contentRange;
  final String? contentType;
  final bool redirectedToP2P;
  final Stream<List<int>> body;
}

/// One ranged GET. Tests swap it for a fake.
abstract interface class RangeFetcher {
  Future<RangeResponse> fetch(Uri uri, ByteRange range, CancelSignal cancel);
}

class HttpRangeFetcher implements RangeFetcher {
  final _client = HttpClient()
    ..maxConnectionsPerHost = 6
    ..connectionTimeout = const Duration(seconds: 5)
    ..idleTimeout = const Duration(seconds: 15)
    ..autoUncompress = false
    ..userAgent = BrowserUa.pc;

  @override
  Future<RangeResponse> fetch(
    Uri uri,
    ByteRange range,
    CancelSignal cancel,
  ) async {
    final request = await _client.getUrl(uri);
    cancel.onCancel(request.abort);
    request
      ..followRedirects = true
      ..maxRedirects = 3
      ..headers.set(HttpHeaders.rangeHeader, 'bytes=$range')
      ..headers.set(HttpHeaders.refererHeader, HttpString.baseUrl);
    final response = await request.close();
    return RangeResponse(
      status: response.statusCode,
      contentRange: parseContentRange(
        response.headers.value(HttpHeaders.contentRangeHeader),
      ),
      contentType: response.headers.value(HttpHeaders.contentTypeHeader),
      redirectedToP2P: response.redirects.any(
        (redirect) => isP2PCdnHost(uri.resolveUri(redirect.location).host),
      ),
      body: response,
    );
  }
}
