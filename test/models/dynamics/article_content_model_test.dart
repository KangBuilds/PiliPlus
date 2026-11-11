import 'package:PiliPlus/models/dynamics/article_content_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses positive image dimensions and detects long pictures', () {
    final pic = Pic.fromJson({'width': 100, 'height': 1000.5, 'size': 12});
    expect(pic.width, 100.0);
    expect(pic.height, 1000.5);
    expect(pic.size, 12.0);
    expect(pic.isLongPic, isTrue);
  });

  for (final invalid in [null, 0, -1, '', '100', true]) {
    test('ignores invalid image dimensions: $invalid', () {
      final pic = Pic.fromJson({
        'width': invalid,
        'height': invalid,
        'size': invalid,
      });
      expect(pic.width, isNull);
      expect(pic.height, isNull);
      expect(pic.size, isNull);
      expect(pic.isLongPic, isNull);
    });
  }

  test('validates nested pictures without changing valid dimensions', () {
    final pic = Pic.fromJson({
      'pics': [
        {'width': 1920, 'height': 1080},
        {'width': 0, 'height': 100},
      ],
    });
    expect(pic.pics!.first.isLongPic, isFalse);
    expect(pic.pics!.last.width, isNull);
    expect(pic.pics!.last.height, 100.0);
    expect(pic.pics!.last.isLongPic, isNull);
  });
}
