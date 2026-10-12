// Ported from Make-Bilibili-Great-Than-Ever-Before (MIT, SukkaW):
// src/core/player/cdn-classify.ts and src/core/player/candidates.ts
//
// A signed upgcxcode address is valid on any upgcxcode host: the host is not
// part of the upos signature. So a file can be fetched from every address the
// playurl listed, and from each of those signatures moved onto other mirrors.

final _mirrorRegex = RegExp(
  r'^https?://(?:upos-\w+-(?!302)\w+|(?:upos|proxy)-tf-[^/]+)\.(?:bilivideo|akamaized)\.(?:com|net)/upgcxcode',
);

const _p2pKeywords = [
  '302ppio',
  '302kodo',
  '.mcdn.bilivideo',
  'szbdyd.com',
  '.nexusedgeio.com',
  '.ahdohpiechei.com',
  // A mirror name, but its certificate is the PCDN one (*.bilivideo.cn)
  'upos-sz-mirror14b.bilivideo.com',
];

/// upgcxcode hosts tried even when the playurl does not list them. Never a
/// P2P / PCDN host; Akamai is left out, it only accepts its own signature.
const seedHosts = [
  'upos-sz-mirrorali.bilivideo.com',
  'upos-sz-mirrorhw.bilivideo.com',
  'upos-sz-mirrorbos.bilivideo.com',
  'upos-sz-mirror08c.bilivideo.com',
  'upos-sz-mirrorbd.bilivideo.com',
  'upos-sz-mirrorcos.bilivideo.com',
  'upos-sz-mirrorcoso1.bilivideo.com',
  'upos-sz-mirrorcosb.bilivideo.com',
  'upos-sz-mirrorcosov.bilivideo.com',
  'upos-sz-mirroraliov.bilivideo.com',
  'upos-sz-estgoss.bilivideo.com',
  'cn-hk-eq-01-01.bilivideo.com',
  'cn-hk-eq-01-03.bilivideo.com',
];

bool isP2PCdnHost(String host) {
  if (_p2pKeywords.any(host.contains)) return true;
  // upos-sz-302ppio.bilivideo.com -> *.nexusedgeio.com
  final dot = host.indexOf('.');
  return (dot == -1 ? host : host.substring(0, dot)).contains('302');
}

bool isAkamaiHost(String host) => host.endsWith('.akamaized.net');

final _ipHost = RegExp(r'^(?:\d{1,3}\.){3}\d{1,3}$');

/// Served by a P2P / PCDN node: often slow, sometimes stale, never raced.
bool isP2PUrl(Uri uri) =>
    isP2PCdnHost(uri.host) ||
    _ipHost.hasMatch(uri.host) ||
    (uri.hasPort && uri.port != 443 && uri.port != 80) ||
    (_mirrorRegex.hasMatch(uri.toString()) &&
        uri.queryParameters['os'] == 'mcdn');

/// Akamai addresses carry their own token on top of the upos signature.
bool isAkamaiSigned(Uri uri) =>
    uri.queryParameters.containsKey('hdnts') ||
    (!uri.queryParameters.containsKey('upsig') && isAkamaiHost(uri.host));

/// One URL a file could be fetched from.
class MediaCandidate {
  MediaCandidate(this.uri, {required this.listed});

  final Uri uri;

  /// Listed by the playurl (or chosen by the user's CDN setting), rather than
  /// a listed signature moved onto another host.
  final bool listed;

  String get host => uri.host;

  @override
  String toString() => host;
}

/// Every URL [urls] (the playurl's addresses, preferred first) can be fetched
/// from: the listed ones that are not P2P, then each upos signature on every
/// other upgcxcode host. At most one candidate per host.
List<MediaCandidate> mediaCandidates(Iterable<String> urls) {
  final candidates = <MediaCandidate>[];
  final hosts = <String>{};
  final moved = <Uri>[];

  for (final url in urls) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.isScheme('https') && !uri.isScheme('http')) {
      continue;
    }
    final upgcxcode = uri.path.contains('/upgcxcode/');
    if (!isP2PUrl(uri) && hosts.add(uri.host)) {
      candidates.add(
        MediaCandidate(uri.replace(scheme: 'https'), listed: true),
      );
    }
    if (upgcxcode && !isAkamaiSigned(uri)) {
      moved.add(uri);
    }
  }

  if (moved.isNotEmpty) {
    final signed = moved.first;
    for (final host in seedHosts) {
      if (hosts.add(host)) {
        candidates.add(
          MediaCandidate(
            Uri.parse('https://$host${signed.path}?${signed.query}'),
            listed: false,
          ),
        );
      }
    }
  }
  return candidates;
}
