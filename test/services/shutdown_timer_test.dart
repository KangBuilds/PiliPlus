import 'package:PiliPlus/services/shutdown_timer_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

void main() {
  testWidgets('countdown appears after scheduling and clears after reset', (
    tester,
  ) async {
    await tester.pumpWidget(
      GetMaterialApp(
        builder: FlutterSmartDialog.init(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => shutdownTimerService.showScheduleExitDialog(
                context,
                isFullScreen: false,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('15分钟'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(shutdownTimerService.isActive, isTrue);
    expect(shutdownTimerService.deadline, isNotNull);
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining(RegExp(r'^14:|^15:')), findsOneWidget);
    shutdownTimerService.reset();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.textContaining(RegExp(r'^14:|^15:')), findsNothing);
    expect(shutdownTimerService.deadline, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 200));
      Get.reset();
  });
}
