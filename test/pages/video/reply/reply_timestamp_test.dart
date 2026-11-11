import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart'
    show ReplyInfo, Content;
import 'package:PiliPlus/models/video/play/url.dart';
import 'package:PiliPlus/pages/video/controller.dart';
import 'package:PiliPlus/pages/video/reply/widgets/reply_item_grpc.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';

class _SettingsBox implements Box<dynamic> {
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => defaultValue;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Player implements PlPlayerController {
  final seeks = <(Duration, bool)>[];

  @override
  Future<void> seekTo(Duration position, {bool isSeek = true}) async {
    seeks.add((position, isSeek));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _VideoController extends GetxController implements VideoDetailController {
  @override
  PlayUrlModel data = PlayUrlModel(timeLength: 120000);

  @override
  final _Player plPlayerController = _Player();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final messages = <String>[];

  setUpAll(() {
    GStorage.setting = _SettingsBox();
  });

  setUp(messages.clear);

  tearDown(Get.reset);

  Future<TextSpan> renderTimestamp(
    WidgetTester tester, {
    Map<String, dynamic>? arguments,
    String Function()? getTag,
    String timestamp = '01:23',
  }) async {
    final originalDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => messages.add(message ?? '');
    try {
      final reply = ReplyInfo(content: Content(message: timestamp));
      final item = ReplyItemGrpc(
        replyItem: reply,
        replyLevel: 1,
        getTag: getTag,
      );
      await tester.pumpWidget(
        GetMaterialApp(
          builder: FlutterSmartDialog.init(),
          home: Scaffold(
            body: TextButton(
              onPressed: () => Get.to(
                () => Scaffold(
                  body: Builder(
                    builder: (context) => item.replyItemRow(
                      context,
                      Theme.of(context).colorScheme,
                      [reply],
                    ),
                  ),
                ),
                arguments: arguments,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final matches = <TextSpan>[];
      void visit(InlineSpan span) {
        if (span is TextSpan) {
          if (span.text?.trim() == timestamp) matches.add(span);
          for (final child in span.children ?? const <InlineSpan>[]) {
            visit(child);
          }
        }
      }

      for (final text in tester.widgetList<RichText>(find.byType(RichText))) {
        visit(text.text);
      }
      return matches.single;
    } finally {
      debugPrint = originalDebugPrint;
    }
  }

  Future<void> tapTimestamp(WidgetTester tester, TextSpan span) async {
    (span.recognizer! as TapGestureRecognizer).onTap!();
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'missing route arguments leave a plain timestamp without lookup errors',
    (tester) async {
      final span = await renderTimestamp(tester);
      expect(span.recognizer, isNull);
      expect(messages.where((m) => m.contains('failed to validate')), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('missing heroTag never falls back to an untagged player', (
    tester,
  ) async {
    Get.put<VideoDetailController>(_VideoController());
    final span = await renderTimestamp(tester, arguments: {});
    expect(span.recognizer, isNull);
    expect(messages.where((m) => m.contains('failed to validate')), isEmpty);
  });

  testWidgets(
    'explicit tag works for validation and tapping without route arguments',
    (tester) async {
      final controller = _VideoController();
      Get.put<VideoDetailController>(controller, tag: 'video');
      final span = await renderTimestamp(tester, getTag: () => 'video');
      expect(span.recognizer, isNotNull);
      await tapTimestamp(tester, span);
      expect(controller.plPlayerController.seeks, [
        (const Duration(seconds: 83), false),
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('route heroTag still supports normal timestamp seeks', (
    tester,
  ) async {
    final controller = _VideoController();
    Get.put<VideoDetailController>(controller, tag: 'video');
    final span = await renderTimestamp(tester, arguments: {'heroTag': 'video'});
    await tapTimestamp(tester, span);
    expect(controller.plPlayerController.seeks, [
      (const Duration(seconds: 83), false),
    ]);
  });

  testWidgets('explicit tag takes precedence over route heroTag when tapping', (
    tester,
  ) async {
    final explicit = _VideoController();
    final route = _VideoController();
    Get
      ..put<VideoDetailController>(explicit, tag: 'explicit')
      ..put<VideoDetailController>(route, tag: 'route');
    final span = await renderTimestamp(
      tester,
      arguments: {'heroTag': 'route'},
      getTag: () => 'explicit',
    );
    await tapTimestamp(tester, span);
    expect(explicit.plPlayerController.seeks, hasLength(1));
    expect(route.plPlayerController.seeks, isEmpty);
  });

  testWidgets('timestamps beyond the video duration remain plain text', (
    tester,
  ) async {
    Get.put<VideoDetailController>(_VideoController(), tag: 'video');
    final span = await renderTimestamp(
      tester,
      arguments: {'heroTag': 'video'},
      timestamp: '10:00',
    );
    expect(span.recognizer, isNull);
  });
}
