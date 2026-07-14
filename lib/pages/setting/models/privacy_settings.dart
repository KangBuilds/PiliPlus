import 'package:PiliPlus/pages/setting/models/model.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

List<SettingsModel> get privacySettings => [
  NormalModel(
    onTap: (context, setState) {
      if (!Accounts.main.isLogin) {
        SmartDialog.showToast('登录后查看');
        return;
      }
      Get.toNamed('/blackListPage');
    },
    title: '黑名单管理',
    subtitle: '已拉黑用户',
    leading: const Icon(Icons.block),
  ),
];
