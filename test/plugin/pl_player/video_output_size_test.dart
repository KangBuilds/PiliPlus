import 'package:PiliPlus/plugin/pl_player/utils/video_output_size.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sizes a 1080p texture to an iPhone 15 Pro inline viewport', () {
    final size = calculateVideoOutputSize(
      viewport: const Size(393, 221),
      source: const Size(1920, 1080),
      devicePixelRatio: 3,
      fit: BoxFit.contain,
    );

    expect(size, const Size(1179, 663));
  });

  test('never upscales beyond the source texture', () {
    final size = calculateVideoOutputSize(
      viewport: const Size(852, 393),
      source: const Size(1920, 1080),
      devicePixelRatio: 3,
      fit: BoxFit.contain,
    );

    expect(size, const Size(1920, 1080));
  });
}
