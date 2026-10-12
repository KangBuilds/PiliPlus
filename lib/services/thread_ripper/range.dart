// Ported from Make-Bilibili-Great-Than-Ever-Before (MIT, SukkaW):
// src/core/player/range.ts and src/modules/thread-ripper/classify.ts

/// Inclusive byte range, as used by HTTP `Range` / `Content-Range`.
class ByteRange {
  const ByteRange(this.start, this.end);

  final int start;
  final int end;

  int get length => end - start + 1;

  @override
  bool operator ==(Object other) =>
      other is ByteRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => '$start-$end';
}

class ContentRange extends ByteRange {
  const ContentRange(super.start, super.end, this.total);

  /// `null` when the server answered `bytes a-b/*`.
  final int? total;
}

/// What a player asked for: `end == null` for an open-ended `bytes=N-`.
typedef RequestedRange = ({int start, int? end});

final _rangeHeader = RegExp(r'^bytes=(\d+)-(\d*)$', caseSensitive: false);

/// A single `Range: bytes=a-b` or `bytes=a-` header; anything else (suffix
/// ranges, several ranges) returns `null`.
RequestedRange? parseRangeHeader(String value) {
  final match = _rangeHeader.firstMatch(value.trim());
  if (match == null) return null;
  final start = int.tryParse(match[1]!);
  if (start == null) return null;
  if (match[2]!.isEmpty) return (start: start, end: null);
  final end = int.tryParse(match[2]!);
  if (end == null || end < start) return null;
  return (start: start, end: end);
}

final _contentRange = RegExp(
  r'^bytes (\d+)-(\d+)/(\d+|\*)$',
  caseSensitive: false,
);

ContentRange? parseContentRange(String? value) {
  if (value == null) return null;
  final match = _contentRange.firstMatch(value.trim());
  if (match == null) return null;
  final start = int.tryParse(match[1]!);
  final end = int.tryParse(match[2]!);
  if (start == null || end == null || end < start) return null;
  if (match[3] == '*') return ContentRange(start, end, null);
  final total = int.tryParse(match[3]!);
  if (total == null || total <= end) return null;
  return ContentRange(start, end, total);
}

/// How one ranged request to one host went.
enum MediaOutcome {
  ok,

  /// A 206 without `Content-Range`: which bytes came back is unknown.
  unverifiable,

  /// A 206 for other bytes than asked for.
  badRange,

  /// The file ends before the range does.
  eofClamp,

  /// The host has another version of the file (another total size).
  staleObject,

  /// 200: the host ignores `Range`.
  noRange,

  /// Redirected onto a P2P CDN.
  redirect,

  /// 401 / 403: the host does not accept this signature.
  refused,

  /// 404 / 410.
  missing,
  throttled,
  serverError,

  /// Headers came, the body broke off.
  truncated,
  network,
  canceled,
}

class ResponseVerdict {
  const ResponseVerdict(this.outcome, [this.total]);

  final MediaOutcome outcome;

  /// The file's total size, when the response is valid.
  final int? total;
}

ResponseVerdict classifyResponse({
  required int status,
  required ContentRange? contentRange,
  required ByteRange expected,
  required int? expectedTotal,
  bool redirectedToP2P = false,
}) {
  if (redirectedToP2P) return const ResponseVerdict(.redirect);
  if (status == 206) {
    if (contentRange == null) return const ResponseVerdict(.unverifiable);
    if (contentRange.start != expected.start) {
      return const ResponseVerdict(.badRange);
    }
    if (contentRange.end != expected.end) {
      final clamped =
          contentRange.end < expected.end &&
          contentRange.total != null &&
          contentRange.end == contentRange.total! - 1;
      return ResponseVerdict(clamped ? .eofClamp : .badRange);
    }
    if (expectedTotal != null &&
        contentRange.total != null &&
        contentRange.total != expectedTotal) {
      return const ResponseVerdict(.staleObject);
    }
    return ResponseVerdict(.ok, contentRange.total ?? expectedTotal);
  }
  return ResponseVerdict(switch (status) {
    200 => .noRange,
    401 || 403 => .refused,
    404 || 410 => .missing,
    416 => .eofClamp,
    412 || 429 || 503 => .throttled,
    _ => .serverError,
  });
}

/// The host does not have this file, or a different version of it: it is no
/// use for the rest of this file.
bool isFileLevelFailure(MediaOutcome outcome) => switch (outcome) {
  .missing || .staleObject || .noRange || .refused || .redirect => true,
  _ => false,
};
