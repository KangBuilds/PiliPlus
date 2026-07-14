import 'dart:convert';
import 'dart:math';

import 'package:PiliPlus/http/init.dart';
import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'decodes small responses inline and large responses in an isolate',
    () async {
      const smallText = 'PiliPlus';
      final small = Request.responseDecoder(
        const GZipEncoder().encodeBytes(utf8.encode(smallText)),
        RequestOptions(),
        ResponseBody.fromBytes(
          const [],
          200,
          headers: const {
            'content-encoding': ['gzip'],
          },
        ),
      );
      expect(small, smallText);

      final random = Random(0);
      final largeText = String.fromCharCodes(
        List.generate(100 * 1024, (_) => 32 + random.nextInt(95)),
      );
      final large = Request.responseDecoder(
        const GZipEncoder().encodeBytes(utf8.encode(largeText)),
        RequestOptions(),
        ResponseBody.fromBytes(
          const [],
          200,
          headers: const {
            'content-encoding': ['gzip'],
          },
        ),
      );
      expect(large, isA<Future<String>>());
      expect(await large, largeText);
    },
  );
}
