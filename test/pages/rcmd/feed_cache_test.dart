import 'dart:io';

import 'package:PiliPlus/pages/rcmd/feed_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late File file;
  var now = DateTime(2026, 11, 14, 9);

  RcmdFeedCache cache() => RcmdFeedCache(file, now: () => now);

  List<Map<String, Object>> items(int from, int count) => [
    for (var i = from; i < from + count; i++) {'id': i},
  ];

  setUp(() {
    dir = Directory.systemTemp.createTempSync('rcmd_feed_cache');
    file = File('${dir.path}/rcmd_feed.json');
    now = DateTime(2026, 11, 14, 9);
  });

  tearDown(() => dir.deleteSync(recursive: true));

  test('has nothing before anything is kept', () async {
    expect(await cache().read('app:0'), isNull);
  });

  test('gives back the first page on the next launch', () async {
    await cache().add('app:0', items(0, 10), fresh: true);
    expect(await cache().read('app:0'), items(0, 10));
  });

  test('is kept apart for each source and account', () async {
    await cache().add('app:0', items(0, 10), fresh: true);
    expect(await cache().read('web:0'), isNull);
    expect(await cache().read('app:42'), isNull);
  });

  test('adds later pages up to the limit', () async {
    final c = cache();
    await c.add('app:0', items(0, 10), fresh: true);
    await c.add('app:0', items(10, 10), fresh: false);
    await c.add('app:0', items(20, 10), fresh: false);
    await c.add('app:0', items(30, 10), fresh: false);
    expect(await cache().read('app:0'), items(0, RcmdFeedCache.maxItems));
  });

  test('a refresh replaces what was kept', () async {
    final c = cache();
    await c.add('app:0', items(0, 10), fresh: true);
    await c.add('app:0', items(10, 10), fresh: false);
    await c.add('app:0', items(100, 10), fresh: true);
    expect(await cache().read('app:0'), items(100, 10));
  });

  test('is not shown once too old', () async {
    await cache().add('app:0', items(0, 10), fresh: true);
    now = now.add(RcmdFeedCache.maxAge + const Duration(minutes: 1));
    expect(await cache().read('app:0'), isNull);
  });

  test('is ignored when unreadable', () async {
    file.writeAsStringSync('{"v": 1, "key": "app:0", "at": ');
    expect(await cache().read('app:0'), isNull);
  });
}
