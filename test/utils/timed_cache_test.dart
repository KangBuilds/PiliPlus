import 'package:PiliPlus/utils/timed_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  var now = DateTime(2026);
  late TimedCache<String> cache;

  setUp(() {
    now = DateTime(2026);
    cache = TimedCache<String>(
      maxAge: const Duration(minutes: 30),
      maxEntries: 2,
      now: () => now,
    );
  });

  test('hands out an answer with the time it was fetched', () {
    cache.put('a', 'urls');
    now = now.add(const Duration(minutes: 29));

    final hit = cache.get('a');
    expect(hit?.value, 'urls');
    expect(hit?.at, DateTime(2026));
  });

  test('an answer past its age is gone', () {
    cache.put('a', 'urls');
    now = now.add(const Duration(minutes: 31));

    expect(cache.get('a'), isNull);
    // ...for good, not only this once
    now = DateTime(2026);
    expect(cache.get('a'), isNull);
  });

  test('drops the least recently used when full', () {
    cache
      ..put('a', '1')
      ..put('b', '2')
      ..get('a')
      ..put('c', '3');

    expect(cache.get('b'), isNull);
    expect(cache.get('a')?.value, '1');
    expect(cache.get('c')?.value, '3');
  });

  test('a new answer replaces the old one and its time', () {
    cache.put('a', 'old');
    now = now.add(const Duration(minutes: 20));
    cache.put('a', 'fresh');
    now = now.add(const Duration(minutes: 20));

    expect(cache.get('a')?.value, 'fresh');
  });
}
