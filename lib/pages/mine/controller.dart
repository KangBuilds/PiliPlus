import 'package:PiliPlus/http/fav.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/search.dart';
import 'package:PiliPlus/http/user.dart';
import 'package:PiliPlus/models/common/account_type.dart';
import 'package:PiliPlus/models/user/info.dart';
import 'package:PiliPlus/models/user/stat.dart';
import 'package:PiliPlus/models_new/fav/fav_folder/data.dart';
import 'package:PiliPlus/models_new/history/list.dart';
import 'package:PiliPlus/models_new/later/list.dart';
import 'package:PiliPlus/pages/common/common_data_controller.dart';
import 'package:PiliPlus/services/account_service.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/extension/scroll_controller_ext.dart';
import 'package:PiliPlus/utils/id_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';

class MineController extends CommonDataController<FavFolderData, FavFolderData>
    with AccountMixin {
  @override
  AccountService accountService = Get.find<AccountService>();

  int? favFolderCount;

  final laterList = <LaterItemModel>[].obs;
  final historyList = <HistoryItemModel>[].obs;

  // 用户信息 头像、昵称、lv
  final Rx<UserInfoData> userInfo = UserInfoData().obs;
  // 用户状态 动态、关注、粉丝
  final Rx<UserStat> userStat = const UserStat().obs;

  static RxBool anonymity =
      (Accounts.account.isNotEmpty && !Accounts.heartbeat.isLogin).obs;

  @override
  void onInit() {
    super.onInit();
    UserInfoData? userInfoCache = Pref.userInfoCache;
    if (userInfoCache != null) {
      userInfo.value = userInfoCache;
      queryData();
      queryVideoPreviews();
      queryUserInfo();
    }
  }

  Future<void> queryVideoPreviews() => Future.wait([
    UserHttp.seeYouLater(page: 1).then((res) {
      if (res case Success(:final response)) {
        laterList.assignAll(response.list ?? const []);
      }
    }),
    UserHttp.historyList(type: 'all').then((res) {
      if (res case Success(:final response)) {
        historyList.assignAll(
          response.list?.where((item) => item.history.business == 'archive') ??
              const [],
        );
      }
    }),
  ]);

  Future<void> openLater(LaterItemModel item) async {
    if (item.isPugv ?? false) {
      PageUtils.viewPugv(seasonId: item.aid);
      return;
    }
    await _openVideo(
      aid: item.aid,
      bvid: item.bvid,
      cid: item.cid,
      cover: item.pic,
      title: item.title,
    );
  }

  Future<void> openHistory(HistoryItemModel item) => _openVideo(
    aid: item.history.oid,
    bvid: item.history.bvid,
    cid: item.history.cid,
    cover: item.cover?.isNotEmpty == true
        ? item.cover
        : item.covers?.firstOrNull,
    title: item.title,
  );

  Future<void> _openVideo({
    required int? aid,
    required String? bvid,
    required int? cid,
    required String? cover,
    required String? title,
  }) async {
    if (aid == null && bvid == null) return;
    bvid ??= IdUtils.av2bv(aid!);
    final videoInfo = cid == null
        ? await SearchHttp.ab2cWithDimension(aid: aid, bvid: bvid)
        : null;
    cid ??= videoInfo?.cid;
    if (cid != null) {
      PageUtils.toVideoPage(
        aid: aid,
        bvid: bvid,
        cid: cid,
        cover: cover,
        title: title,
        dimension: videoInfo?.dimension,
      );
    }
  }

  bool get isLogin {
    if (!accountService.isLogin.value) {
      // SmartDialog.showToast('账号未登录');
      return false;
    }
    return true;
  }

  Future<void> queryUserInfo() async {
    final res = await UserHttp.userInfo();
    if (res case Success(:final response)) {
      if (response.isLogin == true) {
        userInfo.value = response;
        if (response != Pref.userInfoCache) {
          GStorage.userInfo.put('userInfoCache', response);
        }
        accountService
          ..face.value = response.face!
          ..isLogin.value = true;
      } else {
        _onLogoutMain();
        return;
      }
    } else {
      final errMsg = res.toString();
      SmartDialog.showToast(errMsg);
      if (errMsg == '账号未登录') {
        _onLogoutMain();
        return;
      }
    }
    queryUserStatOwner();
  }

  void _onLogoutMain() => Accounts.deleteAll({Accounts.main});

  Future<void> queryUserStatOwner() async {
    final res = await UserHttp.userStatOwner();
    if (res case Success(:final response)) {
      userStat.value = response;
    }
  }

  @override
  bool customHandleResponse(bool isRefresh, Success<FavFolderData> response) {
    favFolderCount = response.response.count;
    loadingState.value = response;
    return true;
  }

  @override
  Future<LoadingState<FavFolderData>> customGetData() {
    return FavHttp.userfavFolder(
      pn: 1,
      ps: 20,
      mid: Accounts.main.mid,
    );
  }

  static void onChangeAnonymity() {
    if (Accounts.account.isEmpty) {
      SmartDialog.showToast('请先登录');
      return;
    }
    final newVal = !anonymity.value;
    anonymity.value = newVal;
    if (newVal) {
      SmartDialog.dismiss();
      SmartDialog.show<bool>(
        clickMaskDismiss: false,
        usePenetrate: true,
        displayTime: const Duration(seconds: 2),
        alignment: Alignment.bottomCenter,
        builder: (context) {
          final theme = Theme.of(context);
          final style = TextStyle(
            color: theme.colorScheme.onSecondaryContainer,
          );
          return ColoredBox(
            color: theme.colorScheme.secondaryContainer,
            child: Padding(
              padding: EdgeInsets.only(
                top: 15,
                left: 20,
                right: 20,
                bottom: MediaQuery.viewPaddingOf(context).bottom + 15,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      const Icon(MdiIcons.incognito, size: 20),
                      const SizedBox(width: 10),
                      Text('已进入无痕模式', style: theme.textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '搜索不携带身份信息\n'
                    '不产生查询或播放记录\n'
                    '点赞等其它操作不受影响',
                    style: theme.textTheme.bodySmall,
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      TextButton(
                        onPressed: () {
                          SmartDialog.dismiss(result: true);
                          SmartDialog.showToast('已设为永久无痕模式');
                        },
                        child: Text('保存为永久', style: style),
                      ),
                      const SizedBox(width: 10),
                      TextButton(
                        onPressed: () {
                          SmartDialog.dismiss();
                          SmartDialog.showToast('已设为临时无痕模式');
                        },
                        child: Text('仅本次（默认）', style: style),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ).then((res) {
        if (res == false) {
          return;
        }
        res == true
            ? Accounts.set(AccountType.heartbeat, AnonymousAccount())
            : Accounts.accountMode[AccountType.heartbeat.index] =
                  AnonymousAccount();
      });
    } else {
      Accounts.set(AccountType.heartbeat, Accounts.main);
      SmartDialog.dismiss(result: false);
      SmartDialog.show(
        clickMaskDismiss: false,
        usePenetrate: true,
        displayTime: const Duration(seconds: 1),
        alignment: Alignment.bottomCenter,
        builder: (context) {
          final theme = Theme.of(context);
          return ColoredBox(
            color: theme.colorScheme.secondaryContainer,
            child: Padding(
              padding: EdgeInsets.only(
                top: 15,
                left: 20,
                right: 20,
                bottom: MediaQuery.viewPaddingOf(context).bottom + 15,
              ),
              child: Row(
                children: [
                  const Icon(MdiIcons.incognitoOff, size: 20),
                  const SizedBox(width: 10),
                  Text('已退出无痕模式', style: theme.textTheme.titleMedium),
                ],
              ),
            ),
          );
        },
      );
    }
  }

  void push(String name) {
    late final mid = userInfo.value.mid;
    if (isLogin && mid != null) {
      Get.toNamed('/$name?mid=$mid');
    }
  }

  void onLogin([bool longPress = false]) {
    if (!accountService.isLogin.value || longPress) {
      Get.toNamed('/loginPage');
    } else {
      Get.toNamed('/member?mid=${userInfo.value.mid}');
    }
  }

  @override
  Future<void> onRefresh({bool isManual = true}) {
    if (!accountService.isLogin.value) {
      return Future.syncValue(null);
    }
    queryUserInfo();
    return Future.wait([super.onRefresh(), queryVideoPreviews()]).whenComplete(
      () {
        if (isManual) {
          scrollController.jumpToTop();
        }
      },
    );
  }

  @override
  void onChangeAccount(bool isLogin) {
    if (isLogin) {
      onRefresh();
    } else {
      userInfo.value = UserInfoData();
      userStat.value = const UserStat();
      laterList.clear();
      historyList.clear();
      loadingState.value = LoadingState.loading();
    }
  }
}
