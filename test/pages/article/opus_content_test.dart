import 'package:PiliPlus/models/dynamics/article_content_model.dart';
import 'package:PiliPlus/pages/article/widgets/opus_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ignores incomplete article cards and renders the next card', (
    tester,
  ) async {
    final paragraphs = [
      {'para_type': 6},
      {
        'para_type': 6,
        'link_card': {'card': <String, dynamic>{}},
      },
      {
        'para_type': 6,
        'link_card': {
          'card': {
            'type': 'LINK_CARD_TYPE_ITEM_NULL',
            'oid': '42',
            'item_null': {'text': 'Still visible'},
          },
        },
      },
    ].map(ArticleContentModel.fromJson).toList();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              OpusContent(opus: paragraphs, images: () => [], maxWidth: 500),
            ],
          ),
        ),
      ),
    );

    expect(find.textContaining('错误的类型'), findsNothing);
    expect(find.textContaining('Still visible'), findsOneWidget);
  });
}
