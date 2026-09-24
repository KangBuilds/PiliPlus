import 'package:PiliPlus/models/home/rcmd/result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses app recommendation card_goto', () {
    final item = RcmdVideoItemAppModel.fromJson({
      'player_args': {'aid': 1, 'cid': 2, 'duration': 3},
      'bvid': 'BV1xx411c7mD',
      'title': 'video',
      'param': '1',
      'card_goto': 'av',
      'args': {'up_name': 'UP', 'up_id': 4},
      'rcmd_reason': '竖屏',
    });

    expect(item.goto, 'av');
    expect(item.owner.name, 'UP');
    expect(item.rcmdReason, isNull);
  });
}
