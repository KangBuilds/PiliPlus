final class CDNService {
  static const auto = CDNService('默认（自动分配）');

  final String desc;
  final String? host;

  const CDNService(this.desc, [this.host]);

  factory CDNService.saved(String? host) =>
      host == null ? auto : CDNService(host, host);

  @override
  bool operator ==(Object other) => other is CDNService && host == other.host;

  @override
  int get hashCode => host.hashCode;
}
