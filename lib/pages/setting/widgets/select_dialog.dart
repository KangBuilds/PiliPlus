import 'package:PiliPlus/http/cdn.dart';
import 'package:PiliPlus/models/common/video/cdn_type.dart';
import 'package:PiliPlus/utils/video_utils.dart';
import 'package:flutter/material.dart';

class SelectDialog<T> extends StatelessWidget {
  final T? value;
  final String title;
  final List<(T, String)> values;
  final Widget Function(BuildContext, int)? subtitleBuilder;
  final bool toggleable;

  const SelectDialog({
    super.key,
    this.value,
    required this.values,
    required this.title,
    this.subtitleBuilder,
    this.toggleable = false,
  });

  @override
  Widget build(BuildContext context) {
    final titleMedium = TextTheme.of(context).titleMedium!;
    return AlertDialog(
      clipBehavior: Clip.hardEdge,
      title: Text(title),
      constraints: subtitleBuilder != null
          ? const BoxConstraints.tightFor(width: 320)
          : null,
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
      content: Material(
        type: .transparency,
        child: SingleChildScrollView(
          child: RadioGroup<T>(
            onChanged: (v) => Navigator.of(context).pop(v ?? value),
            groupValue: value,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(
                values.length,
                (index) {
                  final item = values[index];
                  return RadioListTile<T>(
                    toggleable: toggleable,
                    dense: true,
                    value: item.$1,
                    title: Text(item.$2, style: titleMedium),
                    subtitle: subtitleBuilder?.call(context, index),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CdnSelectDialog extends StatelessWidget {
  const CdnSelectDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<CDNService>>(
      future: CDNHttp.services,
      builder: (context, snapshot) {
        if (snapshot.data case final services?) {
          return SelectDialog<CDNService>(
            title: 'CDN 设置',
            values: services.map((item) => (item, item.desc)).toList(),
            value: VideoUtils.cdnService,
          );
        }
        return AlertDialog(
          title: const Text('CDN 设置'),
          content: snapshot.hasError
              ? const Text('获取 CDN 列表失败，请检查网络')
              : const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(width: 16),
                    Text('正在获取 CDN 列表…'),
                  ],
                ),
        );
      },
    );
  }
}
