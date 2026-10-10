import 'dart:async';

import 'package:PiliPlus/common/widgets/flutter/refresh_indicator.dart'
    as refresh;
import 'package:PiliPlus/common/widgets/refresh_layout.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

class _SettingsBox implements Box<dynamic> {
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => defaultValue;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LayoutCounter extends SingleChildRenderObjectWidget {
  const _LayoutCounter({required this.onLayout, required super.child});

  final VoidCallback onLayout;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLayoutCounter(onLayout);
}

class _RenderLayoutCounter extends RenderProxyBox {
  _RenderLayoutCounter(this.onLayout);

  final VoidCallback onLayout;

  @override
  void performLayout() {
    onLayout();
    super.performLayout();
  }
}

void main() {
  setUpAll(() {
    GStorage.setting = _SettingsBox();
  });

  testWidgets('matches the previous reveal, scale and edge offset', (
    tester,
  ) async {
    final position = AnimationController(vsync: tester, upperBound: 1.5);
    final scale = AnimationController(vsync: tester);
    const indicatorKey = ValueKey('indicator');
    const edgeOffset = 24.0;
    const displacement = 40.0;

    Widget build(bool legacy, double width) {
      const indicator = RepaintBoundary(
        child: RefreshProgressIndicator(key: indicatorKey, value: 0.5),
      );
      const body = SizedBox.expand();
      return MaterialApp(
        home: Center(
          child: SizedBox(
            width: width,
            height: 300,
            child: legacy
                ? Stack(
                    clipBehavior: Clip.none,
                    children: [
                      body,
                      Positioned(
                        top: edgeOffset,
                        left: 0,
                        right: 0,
                        child: SizeTransition(
                          alignment: AlignmentDirectional.bottomStart,
                          sizeFactor: position,
                          child: Padding(
                            padding: const EdgeInsets.only(top: displacement),
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: ScaleTransition(
                                scale: scale,
                                child: indicator,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : RefreshLayout(
                    position: position,
                    scale: scale,
                    displacement: displacement,
                    edgeOffset: edgeOffset,
                    body: body,
                    indicator: indicator,
                  ),
          ),
        ),
      );
    }

    for (final width in [320.0, 700.0]) {
      for (final heightFactor in [0.0, 0.5, 1.0, 1.5]) {
        for (final scaleFactor in [0.0, 0.5, 1.0]) {
          position.value = heightFactor;
          scale.value = scaleFactor;
          await tester.pumpWidget(build(true, width));
          final previousRect = tester.getRect(find.byKey(indicatorKey));
          await tester.pumpWidget(build(false, width));
          final rect = tester.getRect(find.byKey(indicatorKey));
          expect(rect.left, closeTo(previousRect.left, 0.001));
          expect(rect.top, closeTo(previousRect.top, 0.001));
          expect(rect.width, closeTo(previousRect.width, 0.001));
          expect(rect.height, closeTo(previousRect.height, 0.001));
          final render = tester.renderObject<RenderRefreshLayout>(
            find.byType(RefreshLayout),
          );
          // The indicator is the only child that should be clipped.
          Rect? indicatorClip;
          render.visitChildren((child) {
            indicatorClip ??= render.describeApproximatePaintClip(child);
          });
          expect(indicatorClip, Rect.fromLTWH(0, 24, width, 89 * heightFactor));
          expect(tester.takeException(), isNull);
        }
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    position.dispose();
    scale.dispose();
  });

  testWidgets('animation ticks repaint without laying out body or indicator', (
    tester,
  ) async {
    final position = AnimationController(vsync: tester)..value = 0.5;
    final scale = AnimationController(vsync: tester)..value = 1;
    final replacement = AnimationController(vsync: tester)..value = 1;
    var bodyLayouts = 0;
    var indicatorLayouts = 0;
    var taps = 0;
    Widget build(Animation<double> animation) => Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RefreshLayout(
          position: animation,
          scale: scale,
          displacement: 40,
          edgeOffset: 0,
          body: _LayoutCounter(
            onLayout: () => bodyLayouts++,
            child: GestureDetector(
              onTap: () => taps++,
              behavior: HitTestBehavior.opaque,
              child: const SizedBox(width: 320, height: 300),
            ),
          ),
          indicator: _LayoutCounter(
            onLayout: () => indicatorLayouts++,
            child: const SizedBox.square(dimension: 49),
          ),
        ),
      ),
    );
    await tester.pumpWidget(build(position));
    final initialBodyLayouts = bodyLayouts;
    final initialIndicatorLayouts = indicatorLayouts;
    position.value = 1;
    scale.value = 0.5;
    await tester.pump();
    expect(bodyLayouts, initialBodyLayouts);
    expect(indicatorLayouts, initialIndicatorLayouts);
    await tester.tapAt(
      tester.getTopLeft(find.byType(RefreshLayout)) + const Offset(160, 50),
    );
    expect(taps, 1);

    await tester.pumpWidget(build(replacement));
    final render = tester.renderObject<RenderRefreshLayout>(
      find.byType(RefreshLayout),
    );
    position.value = 0;
    expect(render.debugNeedsPaint, isFalse);
    replacement.value = 0.25;
    expect(render.debugNeedsPaint, isTrue);
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    replacement.value = 0.75;
    scale.value = 0;
    expect(tester.takeException(), isNull);
    position.dispose();
    replacement.dispose();
    scale.dispose();
  });

  testWidgets('supports shrink-wrapped body with no idle indicator', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RefreshLayout(
              position: AlwaysStoppedAnimation(0),
              scale: AlwaysStoppedAnimation(1),
              displacement: 40,
              edgeOffset: 0,
              body: SizedBox(width: 200, height: 180),
            ),
          ],
        ),
      ),
    );
    expect(tester.getSize(find.byType(RefreshLayout)), const Size(200, 180));
    expect(tester.takeException(), isNull);
  });

  testWidgets('programmatic refresh creates and removes the indicator', (
    tester,
  ) async {
    final key = GlobalKey<refresh.RefreshIndicatorState>();
    final completion = Completer<void>();
    var refreshes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: refresh.RefreshIndicator(
          key: key,
          edgeOffset: 24,
          onRefresh: () {
            refreshes++;
            return completion.future;
          },
          child: ListView(children: const [SizedBox(height: 1000)]),
        ),
      ),
    );
    expect(find.byType(RefreshProgressIndicator), findsNothing);
    final future = key.currentState!.show();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
    expect(refreshes, 1);
    expect(find.byType(RefreshProgressIndicator), findsOneWidget);
    final layout = tester.widget<RefreshLayout>(find.byType(RefreshLayout));
    expect(layout.edgeOffset, 24);
    expect(layout.displacement, refresh.displacement);
    completion.complete();
    await tester.pump();
    await future;
    await tester.pump(const Duration(milliseconds: 220));
    await tester.pump();
    expect(find.byType(RefreshProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final clamping in [false, true]) {
    testWidgets('pull refresh and cancellation with clamping=$clamping', (
      tester,
    ) async {
      final completion = Completer<void>();
      var refreshes = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: refresh.RefreshIndicator(
            isClampingScrollPhysics: clamping,
            onRefresh: () {
              refreshes++;
              return completion.future;
            },
            child: ListView(
              physics: clamping
                  ? const ClampingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    )
                  : const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
              children: const [SizedBox(height: 1000)],
            ),
          ),
        ),
      );
      await tester.drag(find.byType(ListView), const Offset(0, 50));
      await tester.pumpAndSettle();
      expect(refreshes, 0);
      expect(find.byType(RefreshProgressIndicator), findsNothing);
      await tester.timedDrag(
        find.byType(ListView),
        const Offset(0, 500),
        const Duration(seconds: 1),
      );
      for (var frame = 0; frame < 60; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(refreshes, 1);
      expect(find.byType(RefreshProgressIndicator), findsOneWidget);
      completion.complete();
      await tester.pumpAndSettle();
      expect(find.byType(RefreshProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
