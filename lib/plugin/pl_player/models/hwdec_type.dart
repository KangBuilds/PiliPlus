// mpv --hwdec=help
enum HwDecType {
  no('no', '启用软解'),
  auto('auto', '启用任意可用解码器'),
  autoSafe('auto-safe', '启用最佳解码器'),
  autoCopy('auto-copy', '启用带拷贝功能的最佳解码器'),
  videotoolbox('videotoolbox', 'VideoToolbox'),
  videotoolboxCopy('videotoolbox-copy', 'VideoToolbox (非直通)'),
  ;

  final String hwdec;
  final String desc;
  const HwDecType(this.hwdec, this.desc);
}
