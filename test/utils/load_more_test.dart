import 'package:PiliPlus/utils/load_more.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('asks for the next page from loadMoreAhead items before the end', () {
    const length = 20;
    expect(isNearEnd(length - loadMoreAhead - 1, length), isFalse);
    expect(isNearEnd(length - loadMoreAhead, length), isTrue);
    expect(isNearEnd(length - 1, length), isTrue);
  });

  test('includes a footer after the last item', () {
    expect(isNearEnd(20, 20), isTrue);
  });

  test('asks at once for a list shorter than loadMoreAhead', () {
    expect(isNearEnd(0, loadMoreAhead - 1), isTrue);
  });
}
