import 'package:PiliPlus/common/widgets/refresh_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget build(bool refreshing) => MaterialApp(
    home: RefreshStatusIndicator(isRefreshing: refreshing),
  );

  testWidgets('does not keep a spinner or ticker alive while idle', (
    tester,
  ) async {
    await tester.pumpWidget(build(false));
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);

    await tester.pumpWidget(build(true));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.binding.transientCallbackCount, greaterThan(0));

    await tester.pumpWidget(build(false));
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('a new refresh survives an in-flight dismissal', (tester) async {
    await tester.pumpWidget(build(true));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpWidget(build(false));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(build(true));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpWidget(build(false));
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
  });
}
