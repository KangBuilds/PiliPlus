import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/grpc/bilibili/im/type.pb.dart';
import 'package:PiliPlus/pages/whisper_detail/widget/chat_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final chat = ChatItem(
    item: Msg(),
    eInfos: null,
    onLongPress: null,
    onSecondaryTapUp: null,
    isOwner: false,
  );

  for (final images in [null, <String>[], 'invalid']) {
    testWidgets('article card tolerates image_urls=$images', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: chat.msgTypeArticleCard_12({
              'rid': 123,
              'title': 'Article title',
              'summary': 'Article summary',
              'image_urls': ?images,
            }, Colors.black),
          ),
        ),
      );
      expect(find.text('Article title'), findsOneWidget);
      expect(find.text('Article summary'), findsOneWidget);
      expect(find.byType(NetworkImgLayer), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('article card ignores invalid title and summary', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: chat.msgTypeArticleCard_12({
            'image_urls': null,
            'title': 123,
            'summary': 456,
          }, Colors.black),
        ),
      ),
    );
    expect(find.byType(Text), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('article card preserves valid image URLs', () {
    final card =
        chat.msgTypeArticleCard_12({
              'image_urls': ['https://example.com/cover.jpg'],
            }, Colors.black)
            as GestureDetector;
    final column = card.child! as Column;
    final row = column.children.first as Row;
    expect(
      (row.children.single as NetworkImgLayer).src,
      'https://example.com/cover.jpg',
    );
  });
}
