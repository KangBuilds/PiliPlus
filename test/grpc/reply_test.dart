import 'package:PiliPlus/common/constants.dart';
import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart';
import 'package:PiliPlus/grpc/grpc_req.dart';
import 'package:PiliPlus/grpc/reply.dart';
import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

class _SettingsBox implements Box<dynamic> {
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => defaultValue;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ReplyInfo _reply(String message, [List<ReplyInfo>? children]) => ReplyInfo(
  content: Content(message: message),
  replies: children,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MainListReply response;

  setUpAll(() {
    GStorage.setting = _SettingsBox();
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
          onRequest: (options, handler) => handler.resolve(
            Response<Uint8List>(
              requestOptions: options,
              statusCode: 200,
              headers: Headers.fromMap({
                'grpc-status': ['0'],
              }),
              data: GrpcReq.compressProtobuf(response.writeToBuffer()),
            ),
          ),
        ),
      );
  });

  setUp(() {
    ReplyGrpc.enableFilter = true;
    ReplyGrpc.replyRegExp = RegExp('blocked');
    ReplyGrpc.antiGoodsReply = false;
  });

  tearDownAll(() => Request.dio.close(force: true));

  Future<MainListReply> load() async => (await ReplyGrpc.mainList(
    oid: 123,
    mode: Mode.MAIN_LIST_HOT,
    offset: null,
    cursorNext: null,
  )).data;

  test(
    'filters children of a retained pinned reply like ordinary replies',
    () async {
      final children = [_reply('blocked'), _reply('keep child')];
      response = MainListReply(
        upTop: _reply('keep pinned', children),
        replies: [_reply('keep ordinary', children)],
      );
      final result = await load();
      expect(result.hasUpTop(), isTrue);
      expect(result.upTop.replies.map((r) => r.content.message), [
        'keep child',
      ]);
      expect(result.replies.single.replies.map((r) => r.content.message), [
        'keep child',
      ]);
    },
  );

  test('still removes a filtered pinned root', () async {
    response = MainListReply(upTop: _reply('blocked', [_reply('keep child')]));
    expect((await load()).hasUpTop(), isFalse);
  });

  test('applies the existing goods filter to pinned children', () async {
    ReplyGrpc.enableFilter = false;
    ReplyGrpc.antiGoodsReply = true;
    response = MainListReply(
      upTop: _reply('keep pinned', [
        _reply(Constants.goodsUrlPrefix),
        _reply('keep child'),
      ]),
    );
    expect((await load()).upTop.replies.map((r) => r.content.message), [
      'keep child',
    ]);
  });

  test('keeps pinned children when filters are disabled', () async {
    ReplyGrpc.enableFilter = false;
    response = MainListReply(upTop: _reply('keep pinned', [_reply('blocked')]));
    expect((await load()).upTop.replies, hasLength(1));
  });
}
