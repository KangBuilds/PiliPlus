import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/models/common/video/video_type.dart';
import 'package:PiliPlus/pages/video/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_status.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';
import 'package:native_device_orientation/native_device_orientation.dart';

class _Box implements Box<dynamic> {
  final stored = <dynamic, dynamic>{};

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      stored[key] ?? (key == 'buvid' ? 'test-buvid' : defaultValue);

  @override
  Future<void> put(dynamic key, dynamic value) async => stored[key] = value;

  @override
  Future<void> putAll(Map<dynamic, dynamic> entries) async =>
      stored.addAll(entries);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Orientation extends NativeDeviceOrientationPlatform {
  @override
  Stream<OrientationParams> onOrientationChanged({
    int? angleDegrees,
    bool checkIsAutoRotate = true,
  }) => const Stream.empty();

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final controllers = <VideoDetailController>[];
  late NativeDeviceOrientationPlatform originalOrientation;
  var requests = 0;

  VideoDetailController open(int cid, {Map? args}) {
    final controller = VideoDetailController()
      ..args = args ?? {}
      ..bvid = 'BV1xx411c7mD'
      ..aid = 1
      ..cid = cid.obs
      ..videoType = VideoType.ugc
      ..isFileSource = false
      ..isVertical = false.obs
      ..minVideoHeight = 100
      ..maxVideoHeight = 200;
    controller.plPlayerController
      ..cacheVideoQa = 80
      ..cacheAudioQa = 30280;
    controllers.add(controller);
    return controller;
  }

  setUpAll(() {
    GStorage.setting = _Box();
    GStorage.video = _Box();
    GStorage.localCache = _Box()
      ..stored[LocalCacheKey.timeStamp] = DateTime.now().millisecondsSinceEpoch
      ..stored[LocalCacheKey.mixinKey] = 'test-mixin-key';
    originalOrientation = NativeDeviceOrientationPlatform.instance;
    NativeDeviceOrientationPlatform.instance = _Orientation();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in [
      SystemChannels.platform,
      const MethodChannel('com.PiliPlus/now_playing'),
      const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
    ]) {
      messenger.setMockMethodCallHandler(channel, (_) async => null);
    }
    Request();
    Request.dio.interceptors
      ..clear()
      ..add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests++;
            handler.resolve(
              Response(
                requestOptions: options,
                data: {
                  'code': 0,
                  'data': {
                    'timelength': 600000,
                    'last_play_time': 100000,
                    'cur_language':
                        options.queryParameters['cur_language'] ?? 'main',
                    'accept_quality': [80],
                    'support_formats': [
                      {
                        'quality': 80,
                        'codecs': ['avc1'],
                      },
                    ],
                    'dash': {
                      'video': [
                        {
                          'id': 80,
                          'baseUrl': 'https://video.test/video.m4s',
                          'codecs': 'avc1',
                          'width': 1280,
                          'height': 720,
                        },
                      ],
                    },
                  },
                },
              ),
            );
          },
        ),
      );
  });

  setUp(() => requests = 0);
  tearDown(() {
    for (final controller in controllers) {
      controller.cid.close();
      controller.plPlayerController.playerStatus.value = PlayerStatus.paused;
      controller.plPlayerController.dispose();
    }
    controllers.clear();
  });
  tearDownAll(() {
    NativeDeviceOrientationPlatform.instance = originalOrientation;
    Request.dio.close(force: true);
  });

  test(
    'exit after twenty seconds resumes past a stale URL and history snapshot',
    () async {
      final first = open(1001);
      await first.queryVideoUrl();
      expect(first.defaultST, const Duration(seconds: 100));
      expect(first.currLang.value, 'main');
      first
        ..playedTime = const Duration(seconds: 120)
        ..makeHeartBeat();

      final reopened = open(1001, args: {'historyProgress': 100000});
      await reopened.queryVideoUrl();
      expect(
        requests,
        1,
        reason: 'The second open must exercise the cached URL',
      );
      expect(reopened.defaultST, const Duration(seconds: 120));

      final link = open(1001, args: {'progress': 12000});
      await link.queryVideoUrl();
      expect(link.defaultST, const Duration(seconds: 12));
    },
  );

  test(
    'without a session checkpoint, freshly loaded history is the resume hint',
    () async {
      final reopened = open(1002, args: {'historyProgress': 120000});
      await reopened.queryVideoUrl();
      expect(reopened.defaultST, const Duration(seconds: 120));
    },
  );

  test('a language change does not split the saved progress', () async {
    final first = open(1003);
    await first.queryVideoUrl();
    first.currLang.value = 'en';
    await first.queryVideoUrl(fromReset: true);
    first
      ..playedTime = const Duration(seconds: 120)
      ..makeHeartBeat();

    final reopened = open(1003);
    await reopened.queryVideoUrl();
    expect(requests, 2);
    expect(reopened.defaultST, const Duration(seconds: 120));

    reopened
      ..playedTime = const Duration(seconds: 40)
      ..makeHeartBeat();
    final rewound = open(1003);
    await rewound.queryVideoUrl();
    expect(rewound.defaultST, const Duration(seconds: 40));
  });

  test(
    'a completed session restarts instead of reusing an older history hint',
    () async {
      final first = open(1004);
      await first.queryVideoUrl();
      first.playedTime = const Duration(minutes: 10);
      first.plPlayerController.playerStatus.value = PlayerStatus.completed;
      first.makeHeartBeat();

      final reopened = open(1004, args: {'historyProgress': 120000});
      await reopened.queryVideoUrl();
      expect(reopened.defaultST, Duration.zero);
    },
  );
}
