import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The first items of the home feed, kept on disk so that the next launch
/// shows them at once while fresh ones are asked for.
///
/// Items are kept as the server sent them, and filtered again when shown, so
/// that what was blocked since stays hidden.
class RcmdFeedCache {
  RcmdFeedCache(this.file, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  /// About two screens of cards: what is seen before the fresh items come.
  static const maxItems = 30;

  /// Older items are not shown: a skeleton is better than last week's feed.
  static const maxAge = Duration(days: 3);

  static const _version = 1;

  final File file;
  final DateTime Function() _now;

  String? _key;
  List _items = const [];
  Future<void> _writing = Future.value();

  /// The items kept for [key], the feed source and the account, if they are
  /// no older than [maxAge].
  Future<List?> read(String key) async {
    try {
      final data = jsonDecode(await file.readAsString());
      if (data is! Map || data['v'] != _version || data['key'] != key) {
        return null;
      }
      final at = DateTime.fromMillisecondsSinceEpoch(data['at'] as int);
      if (_now().difference(at) > maxAge) return null;
      final items = data['items'];
      return items is List && items.isNotEmpty ? items : null;
    } catch (_) {
      // None yet, or unreadable: the feed loads as it would without
      return null;
    }
  }

  /// Keeps the items of a page for [key]: those of a first page, [fresh],
  /// replace what was kept; later pages add to them up to [maxItems].
  Future<void> add(String key, List items, {required bool fresh}) {
    if (fresh || key != _key) {
      _key = key;
      _items = [];
    }
    if (_items.length >= maxItems || items.isEmpty) return _writing;
    _items.addAll(items.take(maxItems - _items.length));
    final json = jsonEncode({
      'v': _version,
      'key': key,
      'at': _now().millisecondsSinceEpoch,
      'items': _items,
    });
    // One at a time, the last one written last
    return _writing = _writing.then((_) => _write(json));
  }

  Future<void> _write(String json) async {
    try {
      // Written whole and then moved, so that a read never sees half of it
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(json, flush: true);
      await tmp.rename(file.path);
    } catch (_) {}
  }
}
