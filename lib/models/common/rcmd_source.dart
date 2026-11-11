import 'package:PiliPlus/models/common/enum_with_label.dart';

enum RcmdSource implements EnumWithLabel {
  app('App 端'),
  web('Web 端'),
  desktop('桌面端 / PC');

  @override
  final String label;

  const RcmdSource(this.label);
}
