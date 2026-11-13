import 'package:PiliPlus/common/widgets/pili_native_glass_tab_bar.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'preserves content selection after search and forwards repeat taps',
    (
      tester,
    ) async {
      final tappedIndices = <int>[];
      var searchTapCount = 0;
      late StateSetter rebuild;
      var selectedIndex = 1;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return Scaffold(
                bottomNavigationBar: PiliNativeGlassTabBar(
                  selectedIndex: selectedIndex,
                  labels: const ['Home', 'Dynamics', 'Mine'],
                  searchLabel: 'Search',
                  onTap: (index) {
                    tappedIndices.add(index);
                    setState(() => selectedIndex = index);
                  },
                  onSearchTap: () => searchTapCount++,
                ),
              );
            },
          ),
        ),
      );

      final finder = find.byType(IOS26NativeTabBar);
      IOS26NativeTabBar bar() => tester.widget<IOS26NativeTabBar>(finder);
      final nativeState = tester.state(finder);
      final beforeSearch = bar();

      await tester.tap(find.text('Search'));
      await tester.pump();

      expect(searchTapCount, 1);
      expect(tappedIndices, isEmpty);
      expect(bar().selectedIndex, 1);
      expect(identical(bar(), beforeSearch), isFalse);
      expect(tester.state(finder), same(nativeState));
      expect(
        MediaQuery.platformBrightnessOf(tester.element(finder)),
        Brightness.dark,
      );

      for (var count = 0; count < 2; count++) {
        await tester.tap(find.text('Dynamics'));
        await tester.pump();
      }
      expect(tappedIndices, [1, 1]);

      await tester.tap(find.text('Mine'));
      await tester.pump();
      expect(tappedIndices, [1, 1, 2]);
      expect(bar().selectedIndex, 2);

      rebuild(() => selectedIndex = 0);
      await tester.pump();
      expect(bar().selectedIndex, 0);

      bar().onTap(3);
      await tester.pump();
      expect(searchTapCount, 2);
      expect(bar().selectedIndex, 0);
      expect(tappedIndices, [1, 1, 2]);
    },
  );
}
