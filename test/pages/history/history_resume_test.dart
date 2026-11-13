import 'package:PiliPlus/models_new/history/history.dart';
import 'package:PiliPlus/models_new/history/list.dart';
import 'package:PiliPlus/pages/common/multi_select/base.dart';
import 'package:PiliPlus/pages/history/widgets/item.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';

class _SettingsBox implements Box<dynamic> {
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => defaultValue;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Selection implements MultiSelectBase<HistoryItemModel> {
  @override
  final enableMultiSelect = false.obs;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() {
    GStorage.setting = _SettingsBox();
  });
  tearDown(Get.reset);

  testWidgets('reopening a history row does not force its old progress', (
    tester,
  ) async {
    final item = HistoryItemModel(
      history: History(
        oid: 1,
        bvid: 'BV1xx411c7mD',
        cid: 2,
        business: 'archive',
      ),
      title: 'History video',
      videos: 1,
      viewAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      progress: 42,
    );
    final opened = <Map>[];
    await tester.pumpWidget(
      GetMaterialApp(
        initialRoute: '/',
        getPages: [
          GetPage(
            name: '/',
            page: () => Scaffold(
              body: SizedBox(
                height: 110,
                child: HistoryItem(
                  item: item,
                  ctr: _Selection(),
                  onDelete: (_, _) {},
                ),
              ),
            ),
          ),
          GetPage(
            name: '/videoV',
            page: () {
              opened.add(Map.of(Get.arguments as Map));
              return const Scaffold(body: Text('Playing video'));
            },
          ),
        ],
      ),
    );

    for (var visit = 0; visit < 2; visit++) {
      await tester.tap(find.text('History video'));
      await tester.pumpAndSettle();
      expect(opened.last['bvid'], item.history.bvid);
      expect(opened.last['cid'], item.history.cid);
      expect(opened.last['historyProgress'], 42000);
      expect(
        opened.last.containsKey('progress'),
        isFalse,
        reason: 'A history snapshot is a resume hint, not an explicit seek',
      );
      Get.back<void>();
      await tester.pumpAndSettle();
    }
    expect(item.progress, 42);

    // A link to a specific moment still deliberately overrides resume history.
    PageUtils.toVideoPage(
      aid: 1,
      bvid: item.history.bvid,
      cid: 2,
      progress: 12000,
    );
    await tester.pumpAndSettle();
    expect(opened.last['progress'], 12000);
  });
}
