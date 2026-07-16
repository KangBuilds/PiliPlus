import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/msg.dart';
import 'package:PiliPlus/models/common/dynamic/dynamic_badge_mode.dart';
import 'package:PiliPlus/models/common/msg/msg_unread_type.dart';
import 'package:PiliPlus/models/common/nav_bar_config.dart';
import 'package:PiliPlus/pages/dynamics/controller.dart';
import 'package:PiliPlus/pages/home/controller.dart';
import 'package:PiliPlus/services/account_service.dart';
import 'package:PiliPlus/utils/extension/get_ext.dart';
import 'package:PiliPlus/utils/feed_back.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:collection/collection.dart';
import 'package:easy_debounce/easy_throttle.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class MainController extends GetxController with GetSingleTickerProviderStateMixin {
  final AccountService accountService = Get.find<AccountService>();

  final navigationBars = NavigationBarType.values;

  late dynamic controller;
  final RxInt selectedIndex = Pref.defaultHomePage.index.obs;

  late final dynamicController = Get.putOrFind(DynamicsController.new);

  late final homeController = Get.putOrFind(HomeController.new);

  late DynamicBadgeMode msgBadgeMode = Pref.msgBadgeMode;
  late Set<MsgUnReadType> msgUnReadTypes = Pref.msgUnReadTypeV2;
  late final RxString msgUnReadCount = ''.obs;
  late int lastCheckUnreadAt = 0;

  final mainTabBarView = Pref.mainTabBarView;

  late bool directExitOnBack = Pref.directExitOnBack;
  late bool showTrayIcon = Pref.showTrayIcon;
  late bool minimizeOnExit = Pref.minimizeOnExit;
  late bool pauseOnMinimize = Pref.pauseOnMinimize;
  late bool isPlaying = false;

  static const _period = 5 * 60 * 1000;
  late int _lastSelectTime = 0;

  @override
  void onInit() {
    super.onInit();
    controller = mainTabBarView
        ? TabController(
            vsync: this,
            initialIndex: selectedIndex.value,
            length: navigationBars.length,
          )
        : PageController(initialPage: selectedIndex.value);

    if (msgBadgeMode != DynamicBadgeMode.hidden) {
      lastCheckUnreadAt = DateTime.now().millisecondsSinceEpoch;
      queryUnreadMsg();
    }
  }

  Future<int> _msgUnread() async {
    if (msgUnReadTypes.contains(MsgUnReadType.pm)) {
      final res = await MsgHttp.msgUnread();
      if (res case Success(:final response)) {
        return response.followUnread +
            response.unfollowUnread +
            response.bizMsgFollowUnread +
            response.bizMsgUnfollowUnread +
            response.unfollowPushMsg +
            response.customUnread;
      }
    }
    return 0;
  }

  Future<int> _msgFeedUnread() async {
    int count = 0;
    final remainTypes = Set<MsgUnReadType>.from(msgUnReadTypes)
      ..remove(MsgUnReadType.pm);
    if (remainTypes.isNotEmpty) {
      final res = await MsgHttp.msgFeedUnread();
      if (res case Success(:final response)) {
        for (final item in remainTypes) {
          switch (item) {
            case MsgUnReadType.pm:
              break;
            case MsgUnReadType.reply:
              count += response.reply;
              break;
            case MsgUnReadType.at:
              count += response.at;
              break;
            case MsgUnReadType.like:
              count += response.like;
              break;
            case MsgUnReadType.sysMsg:
              count += response.sysMsg;
              break;
          }
        }
      }
    }
    return count;
  }

  Future<void> queryUnreadMsg([bool isChangeType = false]) async {
    if (!accountService.isLogin.value ||
        msgUnReadTypes.isEmpty ||
        msgBadgeMode == DynamicBadgeMode.hidden) {
      msgUnReadCount.value = '';
      return;
    }

    final res = await Future.wait([_msgUnread(), _msgFeedUnread()]);

    final count = res.sum;

    final countStr = count == 0
        ? ''
        : count > 99
        ? '99+'
        : count.toString();
    if (msgUnReadCount.value == countStr) {
      if (isChangeType) {
        msgUnReadCount.refresh();
      }
    } else {
      msgUnReadCount.value = countStr;
    }
  }

  void checkDefaultSearch([bool shouldCheck = false]) {
    if (homeController.enableSearchWord) {
      if (shouldCheck &&
          navigationBars[selectedIndex.value] != NavigationBarType.home) {
        return;
      }
      int now = DateTime.now().millisecondsSinceEpoch;
      if (now - homeController.lateCheckSearchAt >= _period) {
        homeController
          ..lateCheckSearchAt = now
          ..querySearchDefault();
      }
    }
  }

  void openSearch() {
    Get.toNamed(
      '/search',
      parameters: homeController.enableSearchWord
          ? {'hintText': homeController.defaultSearch.value}
          : null,
    );
  }

  void toMinePage() => setIndex(NavigationBarType.mine.index);

  void checkUnread([bool shouldCheck = false]) {
    if (accountService.isLogin.value &&
        msgBadgeMode != DynamicBadgeMode.hidden) {
      if (shouldCheck &&
          navigationBars[selectedIndex.value] != NavigationBarType.home) {
        return;
      }
      int now = DateTime.now().millisecondsSinceEpoch;
      if (now - lastCheckUnreadAt >= _period) {
        lastCheckUnreadAt = now;
        queryUnreadMsg();
      }
    }
  }

  void setIndex(int value) {
    feedBack();

    final currentNav = navigationBars[value];
    if (value != selectedIndex.value) {
      selectedIndex.value = value;
      if (mainTabBarView) {
        controller.animateTo(value);
      } else {
        controller.jumpToPage(value);
      }
      if (currentNav == NavigationBarType.home) {
        checkDefaultSearch();
        checkUnread();
      }
    } else {
      int now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastSelectTime < 500) {
        EasyThrottle.throttle(
          'topOrRefresh',
          const Duration(milliseconds: 500),
          () {
            if (currentNav == NavigationBarType.home) {
              homeController.onRefresh();
            } else if (currentNav == NavigationBarType.dynamics) {
              dynamicController.onRefresh();
            }
          },
        );
      } else {
        if (currentNav == NavigationBarType.home) {
          homeController.toTopOrRefresh();
        } else if (currentNav == NavigationBarType.dynamics) {
          dynamicController.toTopOrRefresh();
        }
      }
      _lastSelectTime = now;
    }
  }

  void setSearchBar() => homeController.showTopBar?.value = true;

  @override
  void onClose() {
    controller.dispose();
    super.onClose();
  }
}
