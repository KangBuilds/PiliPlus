import 'dart:async' show FutureOr;
import 'dart:io' show Platform, Directory, File;

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as path;

abstract final class AssetUtils {
  /// from media-kit AssetLoader
  static String tryGetPath(String key) => path.join(
    path.dirname(Platform.resolvedExecutable),
    'Frameworks',
    'App.framework',
    'flutter_assets',
    key,
  );

  static FutureOr<String> getOrCopy(
    String src,
    Iterable<String> files,
    String dst,
  ) async {
    final srcDir = Directory(tryGetPath(src));
    if (srcDir.existsSync()) {
      return srcDir.absolute.path;
    }

    final dstDir = Directory(dst);
    if (!dstDir.existsSync()) {
      await dstDir.create(recursive: true);
    }

    for (final file in files) {
      final targetFile = File(path.join(dst, file));
      if (targetFile.existsSync()) {
        continue;
      }

      try {
        final data = await rootBundle.load('$src/$file');
        await targetFile.writeAsBytes(data.buffer.asUint8List());
      } catch (_) {}
    }
    return dst;
  }
}
