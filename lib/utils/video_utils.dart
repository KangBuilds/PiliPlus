import 'package:PiliPlus/models/common/video/cdn_type.dart';
import 'package:PiliPlus/models/common/video/video_decode_type.dart';
import 'package:PiliPlus/services/thread_ripper/candidates.dart';
import 'package:PiliPlus/services/thread_ripper/thread_ripper.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:collection/collection.dart';

abstract final class VideoUtils {
  static CDNService cdnService = Pref.defaultCDNService;
  static bool disableAudioCDN = Pref.disableAudioCDN;

  static String hostOf(String url) =>
      Uri.tryParse(url)?.host.toLowerCase() ?? '';

  static String formatBitrate(String value) {
    final bitrate = double.tryParse(value);
    return bitrate == null ? '—' : '${(bitrate / 1000).round()} Kbps';
  }

  static String formatFrameRate(String value) {
    final frameRate = double.tryParse(value);
    return frameRate == null ? '' : '@${frameRate.toStringAsFixed(3)}';
  }

  static String getCdnUrl(
    Iterable<String> urls, {
    CDNService? defaultCDNService,
    bool isAudio = false,
  }) {
    final candidates = urls
        .map((url) => url.trim())
        .where((url) => url.isNotEmpty)
        .toSet()
        .toList();
    if (candidates.isEmpty) return '';

    final parsed = [for (final url in candidates) ?Uri.tryParse(url)];
    // Bilibili's own hosts first, then other official ones (Akamai), never a
    // P2P / PCDN node while anything else is listed
    final official = parsed.where((uri) => !isP2PUrl(uri)).toList();
    final preferred = official.where((uri) => uri.host.contains('bilivideo'));
    var selected =
        preferred.firstOrNull ??
        official.firstOrNull ??
        parsed.map(rescueP2PUrl).nonNulls.firstOrNull ??
        parsed.firstOrNull;
    if (selected == null) return candidates.first;

    final host = (defaultCDNService ?? cdnService).host;
    if (host != null &&
        !(isAudio && disableAudioCDN) &&
        !isP2PCdnHost(host) &&
        selected.path.contains('/upgcxcode/')) {
      // A host only accepts its own family of signatures: Akamai its own, the
      // others upos ones. Use a listed address the chosen host accepts
      final signed = acceptsSignatureOf(host, selected)
          ? selected
          : official.firstWhereOrNull(
              (uri) =>
                  uri.path.contains('/upgcxcode/') &&
                  acceptsSignatureOf(host, uri),
            );
      if (signed != null) selected = signed.replace(host: host);
    }

    final url = selected.toString();
    threadRipper.rememberAlternatives(url, candidates);
    return url;
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
