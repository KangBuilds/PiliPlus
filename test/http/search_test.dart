import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses the WBI search suggestion response', () {
    final state = SearchHttp.parseSuggestResponse({
      'code': 0,
      'data': {
        'result': {
          'tag': [
            {'term': 'PiliPlus', 'name': 'PiliPlus'},
          ],
        },
      },
    });

    expect(state, isA<Success>());
    expect((state as Success).response.tag!.single.term, 'PiliPlus');
  });
}
