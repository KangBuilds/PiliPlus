import 'dart:convert';

import 'package:PiliPlus/utils/app_sign.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('includes the equals sign for empty string parameters', () {
    final params = <String, dynamic>{'empty': '', 'query': 'a b&c'};
    AppSign.appSign(params, appkey: 'test-key', appsec: 'test-secret');

    final query = 'appkey=test-key&empty=&query=a%20b%26c&ts=${params['ts']}';
    expect(
      params['sign'],
      md5.convert(utf8.encode('${query}test-secret')).toString(),
    );
  });

  test('preserves repeated values including empty values', () {
    final params = <String, dynamic>{
      'items': <String>['first', '', 'last'],
    };
    AppSign.appSign(params, appkey: 'test-key', appsec: 'test-secret');

    final query =
        'appkey=test-key&items=first&items=&items=last&ts=${params['ts']}';
    expect(
      params['sign'],
      md5.convert(utf8.encode('${query}test-secret')).toString(),
    );
  });
}
