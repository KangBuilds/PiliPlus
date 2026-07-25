import 'package:PiliPlus/utils/grid.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses a fixed column count when configured', () {
    final delegate = SliverGridDelegateWithExtentAndRatio(
      maxCrossAxisExtent: 240,
      crossAxisCount: 3,
    );

    final layout = delegate.getLayout(
      const SliverConstraints(
        axisDirection: AxisDirection.down,
        growthDirection: GrowthDirection.forward,
        userScrollDirection: ScrollDirection.idle,
        scrollOffset: 0,
        precedingScrollExtent: 0,
        overlap: 0,
        remainingPaintExtent: 1024,
        crossAxisExtent: 1024,
        crossAxisDirection: AxisDirection.right,
        viewportMainAxisExtent: 1024,
        remainingCacheExtent: 1024,
        cacheOrigin: 0,
      ),
    );

    expect((layout as SliverGridRegularTileLayout).crossAxisCount, 3);
  });
}
