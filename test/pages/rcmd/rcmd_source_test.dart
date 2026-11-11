import 'dart:async';

import 'package:PiliPlus/http/api.dart';
import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/models/common/rcmd_source.dart';
import 'package:PiliPlus/models/model_rec_video_item.dart';
import 'package:PiliPlus/pages/rcmd/controller.dart';
import 'package:PiliPlus/pages/setting/models/recommend_settings.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';

class _Box implements Box<dynamic> {
  final stored = <dynamic, dynamic>{};

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      stored[key] ?? defaultValue;

  @override
  Future<void> putAll(Map<dynamic, dynamic> entries) async {
    stored.addAll(entries);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> _video(String title) => {
  'id': 1,
  'goto': 'av',
  'title': title,
  'duration': 120,
  'owner': {'mid': 1, 'name': 'UP'},
  'stat': {'view': 10000, 'like': 1000},
};

void _respond(
  RequestOptions options,
  RequestInterceptorHandler handler, {
  String? error,
}) {
  handler.resolve(
    Response<dynamic>(
      requestOptions: options,
      statusCode: 200,
      data: error != null
          ? {'code': -1, 'message': error}
          : {
              'code': 0,
              'data': {
                'items': <dynamic>[],
                'item': [
                  _video(
                    options.queryParameters['plat'] == 1 ? 'desktop' : 'web',
                  ),
                ],
              },
            },
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final setting = _Box();
  final cache = _Box();
  final requests = <RequestOptions>[];
  late void Function(RequestOptions, RequestInterceptorHandler) onRequest;

  setUpAll(() {
    GStorage.setting = setting;
    GStorage.localCache = cache;
    cache.stored.addAll({
      LocalCacheKey.timeStamp: DateTime.now().millisecondsSinceEpoch,
      LocalCacheKey.mixinKey: 'test-key',
      LocalCacheKey.buvid: 'test-buvid',
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
          (_) async => null,
        );
    Request();
    Request.dio.interceptors
      ..clear()
      ..add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options);
            onRequest(options, handler);
          },
        ),
      );
  });

  setUp(() {
    setting.stored.clear();
    requests.clear();
    onRequest = _respond;
  });

  tearDownAll(() => Request.dio.close(force: true));

  RcmdController controller() {
    final result = RcmdController()..page = 0;
    addTearDown(result.onClose);
    return result;
  }

  test('retains the old App/Web choice and prefers a valid new source', () {
    expect(Pref.rcmdSource, RcmdSource.app);
    setting.stored[SettingBoxKey.appRcmd] = false;
    expect(Pref.rcmdSource, RcmdSource.web);
    for (final source in RcmdSource.values) {
      setting.stored[SettingBoxKey.rcmdSource] = source.index;
      expect(Pref.rcmdSource, source);
    }
    for (final invalid in [-1, 3, 'desktop', true]) {
      setting.stored[SettingBoxKey.rcmdSource] = invalid;
      expect(Pref.rcmdSource, RcmdSource.web);
    }
  });

  test('routes each source to its endpoint and request parameters', () async {
    for (final source in RcmdSource.values) {
      setting.stored[SettingBoxKey.rcmdSource] = source.index;
      await controller().queryData();
      final request = requests.last;
      expect(
        request.path,
        source == RcmdSource.app ? Api.recommendListApp : Api.recommendListWeb,
      );
      if (source != RcmdSource.app) {
        expect(request.queryParameters, containsPair('w_rid', isNotEmpty));
        expect(
          request.queryParameters['ps'],
          source == RcmdSource.web ? 20 : 30,
        );
        expect(
          request.queryParameters['feed_version'],
          source == RcmdSource.web ? 'V8' : 'V1',
        );
        expect(request.queryParameters['fresh_idx'], 0);
        if (source == RcmdSource.desktop) {
          expect(request.queryParameters, containsPair('plat', 1));
          expect(request.queryParameters['fresh_type'], 0);
          expect(request.queryParameters['x_num'], 3);
          expect(request.queryParameters['y_num'], 4);
          expect(request.queryParameters['pc_wx_install'], 0);
          expect(request.queryParameters['pc_wx_gm_install'], 0);
          expect(request.queryParameters, isNot(contains('homepage_ver')));
        } else {
          expect(request.queryParameters['version'], 1);
          expect(request.queryParameters['homepage_ver'], 1);
          expect(request.queryParameters['brush'], 0);
          expect(request.queryParameters['fresh_type'], 4);
        }
      }
    }
    await VideoHttp.rcmdVideoList(ps: 30, freshIdx: 1, desktop: true);
    expect(requests.last.queryParameters['fresh_type'], 4);
  });

  for (final loadMore in [false, true]) {
    test(
      'switches source during ${loadMore ? 'load-more' : 'refresh'}',
      () async {
        setting.stored[SettingBoxKey.appRcmd] = false;
        final ctr = controller();
        await ctr.queryData();
        ctr.lastRefreshAt = 1;
        final pending =
            Completer<(RequestOptions, RequestInterceptorHandler)>();
        onRequest = (options, handler) => pending.complete((options, handler));
        final oldRequest = ctr.queryData(!loadMore);
        final (options, handler) = await pending.future;
        ctr.switchSource(RcmdSource.desktop);
        expect(ctr.loadingState.value, isA<Loading>());
        expect(ctr.lastRefreshAt, isNull);
        onRequest = _respond;
        // Discard both old successes and errors before fetching the new source.
        _respond(options, handler, error: loadMore ? 'old error' : null);
        await oldRequest;
        expect(ctr.loadingState.value.data!.map((v) => v.title), ['desktop']);
        expect(ctr.page, 1);
        expect(requests.last.queryParameters['fresh_idx'], 0);
        await ctr.onRefresh();
        expect(ctr.loadingState.value.data!.map((v) => v.title), [
          'desktop',
          'desktop',
        ]);
        expect(ctr.lastRefreshAt, 1);
      },
    );
  }

  test('keeps only the latest source during rapid switches', () async {
    setting.stored[SettingBoxKey.appRcmd] = false;
    final ctr = controller();
    final pending = Completer<(RequestOptions, RequestInterceptorHandler)>();
    onRequest = (options, handler) => pending.complete((options, handler));
    final oldRequest = ctr.queryData();
    final (options, handler) = await pending.future;
    ctr
      ..switchSource(RcmdSource.desktop)
      ..switchSource(RcmdSource.web);
    onRequest = _respond;
    _respond(options, handler);
    await oldRequest;
    expect(ctr.loadingState.value.data!.single.title, 'web');
    expect(requests, hasLength(2));
    expect(requests.last.queryParameters['fresh_idx'], 0);
  });

  test(
    'shows a new-source error even when the old request was load-more',
    () async {
      setting.stored[SettingBoxKey.appRcmd] = false;
      final ctr = controller();
      await ctr.queryData();
      final pending = Completer<(RequestOptions, RequestInterceptorHandler)>();
      onRequest = (options, handler) => pending.complete((options, handler));
      final oldRequest = ctr.onLoadMore();
      final (options, handler) = await pending.future;
      ctr.switchSource(RcmdSource.desktop);
      onRequest = (options, handler) =>
          _respond(options, handler, error: 'failed');
      _respond(options, handler);
      await oldRequest;
      expect(ctr.loadingState.value, const Error('failed'));
      onRequest = _respond;
      await ctr.onReload();
      expect(ctr.loadingState.value.data!.single.title, 'desktop');
    },
  );

  testWidgets('shows source descriptions, persists the choice and reloads', (
    tester,
  ) async {
    setting.stored[SettingBoxKey.appRcmd] = false;
    final ctr = Get.put<RcmdController>(RcmdController());
    ctr.loadingState.value = Success(<RcmdVideoItemModel>[
      RcmdVideoItemModel.fromJson(_video('old')),
    ]);
    await tester.pumpWidget(
      GetMaterialApp(
        builder: FlutterSmartDialog.init(),
        home: Scaffold(body: recommendSettings.first.widget),
      ),
    );
    expect(find.text('Web 端'), findsOneWidget);
    await tester.tap(find.text('首页推荐来源'));
    await tester.pumpAndSettle();
    expect(find.text('App 端'), findsOneWidget);
    expect(find.text('桌面端 / PC'), findsOneWidget);
    expect(find.textContaining('官方桌面客户端'), findsOneWidget);
    await tester.tap(find.text('桌面端 / PC'));
    await tester.pumpAndSettle();
    expect(Pref.rcmdSource, RcmdSource.desktop);
    expect(Pref.appRcmd, false);
    expect(ctr.loadingState.value.data!.single.title, 'desktop');
    expect(find.text('桌面端 / PC'), findsOneWidget);
    final dismissed = SmartDialog.dismiss(status: SmartStatus.allToast);
    await tester.pump(const Duration(milliseconds: 300));
    await dismissed;
    await tester.pumpAndSettle();
    Get.reset();
  });
}
