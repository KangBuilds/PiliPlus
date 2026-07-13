import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/models/common/video/cdn_type.dart';

abstract final class CDNHttp {
  static const _regionUrl =
      'https://kanda-akihito-kun.github.io/ccb/api/region.json';
  static const _cdnUrl =
      'https://kanda-akihito-kun.github.io/ccb/api/cdn.json';

  static List<CDNService>? _cache;
  static Future<List<CDNService>>? _pending;

  static Future<List<CDNService>> get services {
    if (_cache case final services?) return Future.value(services);
    return _pending ??= _fetch();
  }

  static Future<List<CDNService>> _fetch() async {
    try {
      final responses = await Future.wait([
        Request.dio.get<List<dynamic>>(_regionUrl),
        Request.dio.get<Map<String, dynamic>>(_cdnUrl),
      ]);
      final regions = responses[0].data as List<dynamic>? ?? const [];
      final cdns = responses[1].data as Map<String, dynamic>? ?? const {};
      final services = [
        for (final region in regions.whereType<String>())
          for (final value in (cdns[region] as List<dynamic>? ?? const []))
            if (value case final String host when host.isNotEmpty)
              CDNService('$region: $host', host),
      ];
      if (services.isEmpty) throw const FormatException('Empty CDN list');
      return _cache = [CDNService.auto, ...services];
    } finally {
      _pending = null;
    }
  }
}
