import 'package:PiliPlus/http/fav.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/search.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/models/common/video/source_type.dart';
import 'package:PiliPlus/models_new/pugv/season_info/episode.dart';
import 'package:PiliPlus/models_new/pugv/season_info/result.dart';
import 'package:PiliPlus/models_new/video/video_detail/episode.dart'
    hide EpisodeItem;
import 'package:PiliPlus/models_new/video/video_detail/stat_detail.dart';
import 'package:PiliPlus/pages/common/common_intro_controller.dart';
import 'package:PiliPlus/pages/video/reply/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_repeat.dart';
import 'package:PiliPlus/services/service_locator.dart';
import 'package:PiliPlus/utils/id_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/share_utils.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

class PugvIntroController extends CommonIntroController {
  int? seasonId;
  int? epId;
  late final SeasonInfoModel seasonItem;

  @override
  (Object, int) get getFavRidType => (epId!, 24);

  @override
  StatDetail? getStat() => seasonItem.stat;

  late final RxBool isFav = (seasonItem.userStatus?.favored == 1).obs;

  @override
  void onInit() {
    final args = Get.arguments;
    seasonId = args['seasonId'];
    epId = args['epId'];
    seasonItem = args['seasonItem'];
    super.onInit();
  }

  @override
  Future<void> actionLikeVideo() async {
    if (!isLogin) {
      SmartDialog.showToast('账号未登录');
      return;
    }
    final newValue = !hasLike.value;
    final result = await VideoHttp.likeVideo(bvid: bvid, type: newValue);
    if (result case Success(:final response)) {
      SmartDialog.showToast(newValue ? response : '取消赞');
      seasonItem.stat?.like += newValue ? 1 : -1;
      hasLike.value = newValue;
    } else {
      result.toast();
    }
  }

  @override
  Future<void> actionTriple() async {
    SmartDialog.showToast('课程不支持三连');
  }

  @override
  void actionShareVideo(BuildContext context) {
    final episode = seasonItem.episodes!.firstWhere(
      (item) => item.cid == cid.value,
    );
    final url =
        episode.shareUrl ?? 'https://www.bilibili.com/cheese/play/ss$seasonId';
    final title =
        episode.shareCopy ??
        '${seasonItem.title} ${episode.showTitle ?? episode.longTitle ?? ''}';
    showDialog(
      context: context,
      builder: (_) => SimpleDialog(
        clipBehavior: Clip.hardEdge,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          ListTile(
            dense: true,
            title: const Text('复制链接', style: TextStyle(fontSize: 14)),
            onTap: () {
              Get.back();
              Utils.copyText(url);
            },
          ),
          ListTile(
            dense: true,
            title: const Text('其它app打开', style: TextStyle(fontSize: 14)),
            onTap: () {
              Get.back();
              PageUtils.launchURL(url);
            },
          ),
          if (PlatformUtils.isMobile)
            ListTile(
              dense: true,
              title: const Text('分享课程', style: TextStyle(fontSize: 14)),
              onTap: () {
                Get.back();
                ShareUtils.shareText('$title - $url');
              },
            ),
        ],
      ),
    );
  }

  @override
  int get copyright => 1;

  Future<bool> onChangeEpisode(BaseEpisodeItem episode) async {
    try {
      final epId = episode.id!;
      final bvid = episode.bvid ?? this.bvid;
      final aid = episode.aid ?? IdUtils.bv2av(bvid);
      final cid = episode.cid ?? await SearchHttp.ab2c(aid: aid, bvid: bvid);
      if (cid == null) {
        return false;
      }

      this.epId = epId;
      this.bvid = bvid;

      videoDetailCtr
        ..plPlayerController.pause()
        ..makeHeartBeat()
        ..onReset()
        ..epId = epId
        ..bvid = bvid
        ..aid = aid
        ..cid.value = cid
        ..queryVideoUrl();
      if (episode.cover?.isNotEmpty == true) {
        videoDetailCtr.cover.value = episode.cover!;
      }

      if (videoDetailCtr.showReply) {
        try {
          final replyCtr = Get.find<VideoReplyController>(tag: heroTag)
            ..aid = aid;
          if (replyCtr.loadingState.value is! Loading) {
            replyCtr.onReload();
          }
        } catch (_) {}
      }

      hasLater.value = videoDetailCtr.sourceType == SourceType.watchLater;
      this.cid.value = cid;
      queryOnlineTotal();
      queryVideoIntro(episode as EpisodeItem);
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('pugv onChangeEpisode: $e');
      return false;
    }
  }

  @override
  bool prevPlay() {
    final episodes = seasonItem.episodes!;
    var index =
        episodes.indexWhere((e) => e.cid == videoDetailCtr.cid.value) - 1;
    if (index < 0) {
      if (videoDetailCtr.plPlayerController.playRepeat !=
          PlayRepeat.listCycle) {
        return false;
      }
      index = episodes.length - 1;
    }
    onChangeEpisode(episodes[index]);
    return true;
  }

  @override
  bool nextPlay() {
    final episodes = seasonItem.episodes!;
    var index =
        episodes.indexWhere((e) => e.cid == videoDetailCtr.cid.value) + 1;
    if (index >= episodes.length) {
      if (videoDetailCtr.plPlayerController.playRepeat !=
          PlayRepeat.listCycle) {
        return false;
      }
      index = 0;
    }
    onChangeEpisode(episodes[index]);
    return true;
  }

  @override
  void queryVideoIntro([EpisodeItem? episode]) {
    episode ??= seasonItem.episodes!.firstWhere((e) => e.cid == cid.value);
    videoDetail
      ..value.title = episode.showTitle
      ..refresh();
    withAudioService(
      (handler) => handler.onVideoDetailChange(
        episode,
        cid.value,
        heroTag,
        artist: seasonItem.title,
      ),
    );
  }

  Future<void> onFavPugv(bool isFav) async {
    final res = isFav
        ? await FavHttp.delFavPugv(seasonId!)
        : await FavHttp.addFavPugv(seasonId!);
    if (res.isSuccess) {
      this.isFav.value = !isFav;
      SmartDialog.showToast('${isFav ? '取消' : ''}收藏成功');
    } else {
      res.toast();
    }
  }
}
