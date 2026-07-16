import 'package:PiliPlus/models/common/enum_with_label.dart';
import 'package:PiliPlus/pages/dynamics/view.dart';
import 'package:PiliPlus/pages/home/view.dart';
import 'package:PiliPlus/pages/mine/view.dart';
import 'package:flutter/widgets.dart';

enum NavigationBarType implements EnumWithLabel {
  home(
    '首页',
    HomePage(isMainPage: true),
  ),
  dynamics(
    '动态',
    DynamicsPage(),
  ),
  mine(
    '我的',
    MinePage(),
  ),
  ;

  @override
  final String label;
  final Widget page;

  const NavigationBarType(this.label, this.page);
}
