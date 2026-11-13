import 'package:PiliPlus/models_new/history/history.dart';
import 'package:PiliPlus/models_new/history/list.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('converts history progress for playback', () {
    final item = HistoryItemModel(history: History());

    expect(item.playbackProgress, isNull);
    item.progress = 42;
    expect(item.playbackProgress, 42000);
    item.progress = -1;
    expect(item.playbackProgress, 0);
  });
}
