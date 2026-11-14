import 'package:PiliPlus/utils/wbi_sign.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a key is from today only on the same date', () {
    final today = DateTime(2026, 11, 14, 9);
    expect(WbiSign.isSameDay(DateTime(2026, 11, 14, 23, 59), today), isTrue);
    expect(WbiSign.isSameDay(DateTime(2026, 11, 13, 23, 59), today), isFalse);
    // Same day of another month or year, which counted as today before
    expect(WbiSign.isSameDay(DateTime(2026, 10, 14), today), isFalse);
    expect(WbiSign.isSameDay(DateTime(2025, 11, 14), today), isFalse);
  });

  test('reads the mixin key from a nav answer', () {
    // Example from the public WBI signing documentation
    const wbiImg = {
      'img_url':
          'https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png',
      'sub_url':
          'https://i0.hdslb.com/bfs/wbi/4932caff0ff746eab6f01bf08b70ac45.png',
    };
    expect(
      WbiSign.mixinKeyFromNav(wbiImg),
      'ea1db124af3c7062474693fa704f4ff8',
    );
  });
}
