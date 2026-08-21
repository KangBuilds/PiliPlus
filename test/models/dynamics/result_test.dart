import 'package:PiliPlus/models/dynamics/result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ignores game dynamic common cards', () {
    expect(
      DynamicAddModel.fromJson({
        'common': {'sub_type': 'game'},
      }).common,
      isNull,
    );
    expect(
      DynamicAddModel.fromJson({
        'common': {'sub_type': 'other', 'title': 'title'},
      }).common?.title,
      'title',
    );
  });
}
