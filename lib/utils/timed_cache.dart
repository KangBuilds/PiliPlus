/// Recent answers kept for a while, the least recently used dropped first.
///
/// For answers that go stale on their own, like signed play URLs: an entry
/// older than [maxAge] is never handed out.
class TimedCache<T> {
  TimedCache({
    required this.maxAge,
    this.maxEntries = 16,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Duration maxAge;
  final int maxEntries;
  final DateTime Function() _now;
  final _entries = <String, ({T value, DateTime at})>{};

  /// The answer for [key] and when it was fetched; `null` once too old.
  ({T value, DateTime at})? get(String key) {
    final entry = _entries.remove(key);
    if (entry == null) return null;
    if (_now().difference(entry.at) > maxAge) return null;
    _entries[key] = entry;
    return entry;
  }

  void put(String key, T value) {
    _entries
      ..remove(key)
      ..[key] = (value: value, at: _now());
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  void remove(String key) => _entries.remove(key);

  void clear() => _entries.clear();
}
