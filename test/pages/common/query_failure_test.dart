// The lists answered are added to when more is loaded: not const.
// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables

import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/pages/common/common_data_controller.dart';
import 'package:PiliPlus/pages/common/common_list_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the next request does.
typedef _Answer<R> = Future<LoadingState<R>> Function();

class _ListController extends CommonListController<List<int>, int> {
  late _Answer<List<int>> answer;
  bool throwOnHandle = false;

  @override
  Future<LoadingState<List<int>>> customGetData() => answer();

  @override
  void handleListResponse(List<int> dataList) {
    if (throwOnHandle) throw StateError('unexpected field');
  }
}

class _DataController extends CommonDataController<int, int> {
  late _Answer<int> answer;

  @override
  Future<LoadingState<int>> customGetData() => answer();
}

void main() {
  group('a list whose request throws', () {
    test('shows the error on a refresh and can be refreshed again', () async {
      final controller = _ListController()
        ..answer = () async => throw const FormatException('not JSON');

      await controller.queryData();

      expect(controller.isLoading, isFalse);
      expect(controller.loadingState.value, isA<Error>());
      expect(controller.page, 1);

      controller.answer = () async => const Success([1, 2]);
      await controller.onRefresh();

      expect(controller.loadingState.value.dataOrNull, [1, 2]);
      expect(controller.page, 2);
    });

    test('keeps the loaded items when loading more throws', () async {
      final controller = _ListController()
        ..answer = () async => Success([1, 2]);
      await controller.queryData();

      controller.answer = () async => throw const FormatException('not JSON');
      await controller.onLoadMore();

      expect(controller.isLoading, isFalse);
      expect(controller.loadingState.value.dataOrNull, [1, 2]);
      expect(controller.page, 2);

      controller.answer = () async => Success([3]);
      await controller.onLoadMore();

      expect(controller.loadingState.value.dataOrNull, [1, 2, 3]);
      expect(controller.page, 3);
    });

    test('recovers when handling the answer throws', () async {
      final controller = _ListController()
        ..answer = (() async => Success([1]))
        ..throwOnHandle = true;

      await controller.queryData();

      expect(controller.isLoading, isFalse);
      expect(controller.loadingState.value, isA<Error>());

      controller.throwOnHandle = false;
      await controller.onRefresh();

      expect(controller.loadingState.value.dataOrNull, [1]);
    });
  });

  test('a data page whose request throws can be refreshed again', () async {
    final controller = _DataController()
      ..answer = () async => throw const FormatException('not JSON');

    await controller.queryData();

    expect(controller.isLoading, isFalse);
    expect(controller.loadingState.value, isA<Error>());

    controller.answer = () async => const Success(7);
    await controller.onRefresh();

    expect(controller.loadingState.value.dataOrNull, 7);
  });
}
