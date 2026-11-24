import 'dart:async';
import 'dart:io';

import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

LoginAccount _account() => LoginAccount(
  BiliCookieJar.fromJson({
    'DedeUserID': '123',
    'bili_jct': 'csrf',
  }),
  'access-key',
  'refresh-token',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('piliplus-account-test-');
    Hive.init(tempDir.path);
    GStorage.regAdapter();
    Accounts.account = await Hive.openBox<LoginAccount>('account');
  });

  setUp(() => Accounts.account.clear());

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test('late account changes cannot recreate a deleted account', () async {
    final account = _account();
    await account.onChange();
    expect(Accounts.account.containsKey('123'), isTrue);

    final lateResponse = Completer<void>();
    final persistLateResponse = lateResponse.future.then((_) {
      account.cookieJar.saveFromResponse(
        Uri.parse('https://www.bilibili.com'),
        [Cookie('SESSDATA', 'late-cookie')..setBiliDomain()],
      );
      return account.onChange();
    });

    await account.delete();
    lateResponse.complete();
    await persistLateResponse;

    expect(Accounts.account.containsKey('123'), isFalse);
  });

  test(
    'delete tombstone is active before asynchronous deletion completes',
    () async {
      final account = _account();
      await account.onChange();

      final deletion = account.delete();
      await account.onChange();
      await deletion;

      expect(Accounts.account.containsKey('123'), isFalse);
    },
  );

  test(
    'anonymous reset refreshes server cookies and falls back offline',
    () async {
      GStorage.setting = await Hive.openBox('settings');
      GStorage.localCache = await Hive.openBox('localCache');
      await GStorage.localCache.put(LocalCacheKey.buvid, 'test-device');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(
              'dev.fluttercommunity.plus/connectivity_status',
            ),
            (_) async => null,
          );
      Request();
      addTearDown(() => Request.dio.close(force: true));
      var failed = false;
      Request.dio.interceptors
        ..clear()
        ..add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              expect(options.path, '/x/frontend/finger/spi');
              expect(options.extra['account'], isA<NoAccount>());
              handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  data: failed
                      ? {'code': -1}
                      : {
                          'code': 0,
                          'data': {'b_3': 'server-b3', 'b_4': 'server-b4'},
                        },
                ),
              );
            },
          ),
        );
      final account = AnonymousAccount()..activated = true;
      await account.delete();
      expect(account.cookieJar.toJson(), containsPair('buvid3', 'server-b3'));
      expect(account.cookieJar.toJson(), containsPair('buvid4', 'server-b4'));
      expect(account.activated, isFalse);

      failed = true;
      await account.delete();
      final cookies = account.cookieJar.toJson();
      expect(cookies['buvid3'], isNotEmpty);
      expect(cookies, isNot(contains('buvid4')));
    },
  );
}
