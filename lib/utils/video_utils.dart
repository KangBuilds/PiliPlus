import 'package:PiliPlus/models/common/video/cdn_type.dart';
import 'package:PiliPlus/models/common/video/video_decode_type.dart';
import 'package:PiliPlus/utils/storage_pref.dart';

abstract final class VideoUtils {
  static CDNService cdnService = Pref.defaultCDNService;
  static bool disableAudioCDN = Pref.disableAudioCDN;

  static String getCdnUrl(
    Iterable<String> urls, {
    CDNService? defaultCDNService,
    bool isAudio = false,
  }) {
    defaultCDNService ??= cdnService;
    final candidates = urls
        .map((url) => url.trim())
        .where((url) => url.isNotEmpty)
        .toSet()
        .toList();
    if (candidates.isEmpty) return '';

    String hostOf(String url) => Uri.tryParse(url)?.host.toLowerCase() ?? '';
    bool isMcdn(String url) =>
        hostOf(url).contains('mcdn') && hostOf(url).contains('bilivideo');
    bool isBilivideo(String url) =>
        hostOf(url).contains('bilivideo') && !isMcdn(url);

    final preferred = candidates.where(isBilivideo).toList();
    final selected = (preferred.isEmpty ? candidates : preferred).first;

    if (defaultCDNService.host == null || (isAudio && disableAudioCDN)) {
      return selected;
    }
    return Uri.parse(selected).replace(host: defaultCDNService.host).toString();
  }

  static VideoDecodeFormatType selectCodec(
    Iterable<String> codecs,
    List<VideoDecodeFormatType> preferCodecs,
  ) {
    if (preferCodecs.isNotEmpty) {
      int bestIndex = preferCodecs.length;
      for (final e in codecs) {
        for (int i = 0; i < bestIndex; i++) {
          if (preferCodecs[i].codes.any(e.startsWith)) {
            bestIndex = i;
            if (bestIndex == 0) {
              return preferCodecs[0];
            }
            break;
          }
        }
      }
      if (bestIndex < preferCodecs.length) {
        return preferCodecs[bestIndex];
      }
    }
    return VideoDecodeFormatType.fromString(codecs.first);
  }
}
