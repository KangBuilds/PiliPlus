import 'package:PiliPlus/utils/image_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildThumbnailUrl', () {
    const cover = 'http://i0.hdslb.com/bfs/archive/abc.jpg';
    const https = 'https://i0.hdslb.com/bfs/archive/abc.jpg';

    test('asks only for quality without a size', () {
      expect(ImageUtils.buildThumbnailUrl(cover, 10), '$https@10q.webp');
    });

    test('asks the server for the width, rounded up', () {
      expect(
        ImageUtils.buildThumbnailUrl(cover, 10, width: 570),
        '$https@600w_10q.webp',
      );
      expect(
        ImageUtils.buildThumbnailUrl(cover, 10, width: 600),
        '$https@600w_10q.webp',
      );
    });

    test('asks the server for the height, rounded up', () {
      expect(
        ImageUtils.buildThumbnailUrl(cover, 10, height: 321),
        '$https@350h_10q.webp',
      );
    });

    test('ignores sizes of zero', () {
      expect(
        ImageUtils.buildThumbnailUrl(cover, 10, width: 0),
        '$https@10q.webp',
      );
    });

    test('adds the size to parameters already there', () {
      expect(
        ImageUtils.buildThumbnailUrl('$cover@1c.png', 10, width: 90),
        '$https@1c_100w_10q.png',
      );
    });

    test('keeps a size already asked for', () {
      expect(
        ImageUtils.buildThumbnailUrl('$cover@100w_100h_1c', 10, width: 570),
        '$https@100w_100h_1c_10q.webp',
      );
    });

    test('does not resize GIFs', () {
      expect(
        ImageUtils.buildThumbnailUrl(
          'https://i0.hdslb.com/bfs/emote/a.GIF',
          10,
          width: 60,
        ),
        'https://i0.hdslb.com/bfs/emote/a.GIF@10q.webp',
      );
    });
  });
}
