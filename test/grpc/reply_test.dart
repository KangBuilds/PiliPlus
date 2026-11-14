import 'package:PiliPlus/common/constants.dart';
import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart';
import 'package:PiliPlus/grpc/grpc_req.dart';
import 'package:PiliPlus/grpc/reply.dart';
import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/pages/common/common_list_controller.dart';
import 'package:PiliPlus/pages/common/reply_controller.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fixnum/fixnum.dart';
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

class _ReplyController extends ReplyController<MainListReply> {
  late MainListReply response;

  @override
  Future<LoadingState<MainListReply>> customGetData() async =>
      Success(response);

  @override
  List<ReplyInfo> getDataList(MainListReply response) => response.replies;
}

class _PlainListController extends CommonListController<List<int>, int> {
  @override
  Future<LoadingState<List<int>>> customGetData() async => const Success([]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MainListReply response;
  final pages = <MainListReply>[];
  final requests = <MainListReq>[];
  int? failAtRequest;

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
          onRequest: (options, handler) {
            requests.add(
              MainListReq.fromBuffer(
                GrpcReq.decompressProtobuf(options.data as Uint8List),
              ),
            );
            if (pages.isNotEmpty) response = pages.removeAt(0);
            handler.resolve(
              Response<Uint8List>(
                requestOptions: options,
                statusCode: 200,
                headers: Headers.fromMap({
                  'grpc-status': [requests.length == failAtRequest ? '7' : '0'],
                }),
                data: GrpcReq.compressProtobuf(response.writeToBuffer()),
              ),
            );
          },
        ),
      );
  });

  setUp(() {
    pages.clear();
    requests.clear();
    failAtRequest = null;
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

  test(
    'skips filtered pages using cursor next and preserves first-page metadata',
    () async {
      pages.addAll([
        MainListReply(
          cursor: CursorReply(next: Int64(42)),
          subjectControl: SubjectControl(count: Int64(100), upMid: Int64(456)),
          replies: [_reply('blocked')],
        ),
        MainListReply(
          cursor: CursorReply(next: Int64(43)),
          replies: [_reply('keep')],
        ),
      ]);
      final result = await load();
      expect(result.replies.single.content.message, 'keep');
      expect(result.cursor.next, Int64(43));
      expect(result.subjectControl.count, Int64(100));
      expect(requests.map((r) => r.cursor.next), [Int64.ZERO, Int64(42)]);
      expect(
        requests.every(
          (r) => r.oid == Int64(123) && r.cursor.mode == Mode.MAIN_LIST_HOT,
        ),
        isTrue,
      );
    },
  );

  test('stops once the server reports the end of filtered comments', () async {
    response = MainListReply(
      cursor: CursorReply(next: Int64(42), isEnd: true),
      replies: [_reply('blocked')],
    );
    final result = await load();
    expect(result.replies, isEmpty);
    expect(result.cursor.isEnd, isTrue);
    expect(requests, hasLength(1));
  });

  test('a retained pinned reply does not trigger page skipping', () async {
    response = MainListReply(
      cursor: CursorReply(next: Int64(42)),
      upTop: _reply('keep pinned'),
      replies: [_reply('blocked')],
    );
    expect((await load()).hasUpTop(), isTrue);
    expect(requests, hasLength(1));
  });

  test('does not loop forever on repeated or missing cursors', () async {
    pages.addAll([
      MainListReply(
        cursor: CursorReply(next: Int64(42)),
        replies: [_reply('blocked')],
      ),
      MainListReply(
        cursor: CursorReply(next: Int64(42)),
        replies: [_reply('blocked')],
      ),
    ]);
    expect((await load()).replies, isEmpty);
    expect(requests, hasLength(2));
    requests.clear();
    response = MainListReply(replies: [_reply('blocked')]);
    expect((await load()).replies, isEmpty);
    expect(requests, hasLength(1));
  });

  test('returns request errors while skipping filtered pages', () async {
    pages.addAll([
      MainListReply(
        cursor: CursorReply(next: Int64(42)),
        replies: [_reply('blocked')],
      ),
      MainListReply(),
    ]);
    failAtRequest = 2;
    final result = await ReplyGrpc.mainList(
      oid: 123,
      mode: Mode.MAIN_LIST_HOT,
      offset: null,
      cursorNext: null,
    );
    expect(result.isSuccess, isFalse);
    expect(requests, hasLength(2));
  });

  test(
    'empty reply pages respect server end flags instead of list length',
    () async {
      final controller = _ReplyController()
        ..response = MainListReply(cursor: CursorReply(next: Int64(42)));
      await controller.queryData();
      expect(controller.isEnd, isFalse);
      expect(controller.cursorNext, Int64(42));
      controller.response = MainListReply(cursor: CursorReply(isEnd: true));
      await controller.queryData(false);
      expect(controller.isEnd, isTrue);
      controller.onClose();
    },
  );

  test('ordinary empty lists still end pagination', () async {
    final controller = _PlainListController();
    await controller.queryData();
    expect(controller.isEnd, isTrue);
    controller.onClose();
  });
}
