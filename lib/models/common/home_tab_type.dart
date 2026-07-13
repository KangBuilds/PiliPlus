import 'package:PiliPlus/models/common/enum_with_label.dart';
import 'package:PiliPlus/pages/common/common_controller.dart';
import 'package:PiliPlus/pages/hot/controller.dart';
import 'package:PiliPlus/pages/hot/view.dart';
import 'package:PiliPlus/pages/rank/controller.dart';
import 'package:PiliPlus/pages/rank/view.dart';
import 'package:PiliPlus/pages/rcmd/controller.dart';
import 'package:PiliPlus/pages/rcmd/view.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

enum HomeTabType implements EnumWithLabel {
  rcmd('推荐'),
  hot('热门'),
  rank('分区'),
  ;

  @override
  final String label;
  const HomeTabType(this.label);

  ScrollOrRefreshMixin Function() get ctr => switch (this) {
    HomeTabType.rcmd => Get.find<RcmdController>,
    HomeTabType.hot => Get.find<HotController>,
    HomeTabType.rank => Get.find<RankController>,
  };

  Widget get page => switch (this) {
    HomeTabType.rcmd => const RcmdPage(),
    HomeTabType.hot => const HotPage(),
    HomeTabType.rank => const RankPage(),
  };
}
