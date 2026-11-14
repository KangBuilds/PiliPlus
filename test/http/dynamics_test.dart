import 'package:PiliPlus/http/dynamics.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'rejects original content without a repost source before requesting',
    () async {
      final state = await DynamicsHttp.repostDynamic(rawText: '原创动态');

      expect(state, isA<Error>());
      expect((state as Error).errMsg, '缺少转发来源');
    },
  );
}
