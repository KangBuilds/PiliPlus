import 'dart:async';
import 'dart:math';
import 'package:PiliPlus/common/assets.dart';
import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/custom_icon.dart';
import 'package:PiliPlus/common/widgets/flutter/pop_scope.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/keep_alive_wrapper.dart';
import 'package:PiliPlus/common/widgets/route_aware_mixin.dart';
import 'package:PiliPlus/common/widgets/scroll_physics.dart';
import 'package:PiliPlus/common/widgets/sliver/video_header.dart';
import 'package:PiliPlus/common/widgets/svg/play_icon.dart';
import 'package:PiliPlus/models/common/episode_panel_type.dart';
import 'package:PiliPlus/models_new/video/video_detail/episode.dart' as ugc;
import 'package:PiliPlus/models_new/video/video_detail/page.dart';
import 'package:PiliPlus/models_new/video/video_detail/ugc_season.dart';
import 'package:PiliPlus/pages/common/common_intro_controller.dart';
import 'package:PiliPlus/pages/danmaku/view.dart';
import 'package:PiliPlus/pages/episode_panel/view.dart';
import 'package:PiliPlus/pages/video/ai_conclusion/view.dart';
import 'package:PiliPlus/pages/video/controller.dart';
import 'package:PiliPlus/pages/video/introduction/local/controller.dart';
import 'package:PiliPlus/pages/video/introduction/local/view.dart';
import 'package:PiliPlus/pages/video/introduction/pugv/controller.dart';
import 'package:PiliPlus/pages/video/introduction/pugv/view.dart';
import 'package:PiliPlus/pages/video/introduction/ugc/controller.dart';
import 'package:PiliPlus/pages/video/introduction/ugc/view.dart';
import 'package:PiliPlus/pages/video/related/view.dart';
import 'package:PiliPlus/pages/video/reply/controller.dart';
import 'package:PiliPlus/pages/video/reply/view.dart';
import 'package:PiliPlus/pages/video/view_point/view.dart';
import 'package:PiliPlus/pages/video/widgets/header_control.dart';
import 'package:PiliPlus/pages/video/widgets/player_focus.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/fullscreen_mode.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_repeat.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_status.dart';
import 'package:PiliPlus/plugin/pl_player/utils/fullscreen.dart';
import 'package:PiliPlus/plugin/pl_player/view/view.dart';
import 'package:PiliPlus/services/service_locator.dart';
import 'package:PiliPlus/services/shutdown_timer_service.dart'
    show shutdownTimerService;
import 'package:PiliPlus/utils/extension/scroll_controller_ext.dart';
import 'package:PiliPlus/utils/image_utils.dart';
import 'package:PiliPlus/utils/mobile_observer.dart';
import 'package:PiliPlus/utils/num_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/theme_utils.dart';
import 'package:extended_nested_scroll_view/extended_nested_scroll_view.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:get/get.dart';

class VideoDetailPageV extends StatefulWidget {
  const VideoDetailPageV({super.key});

  @override
  State<VideoDetailPageV> createState() => _VideoDetailPageVState();
}

class _VideoDetailPageVState extends State<VideoDetailPageV>
    with RouteAware, RouteAwareMixin, WidgetsBindingObserver {
  final heroTag = Get.arguments['heroTag'];

  late final VideoDetailController videoDetailController;
  late final VideoReplyController _videoReplyController;
  PlPlayerController? plPlayerController;

  // intro ctr
  late final CommonIntroController introController =
      videoDetailController.isFileSource
      ? localIntroController
      : videoDetailController.isUgc
      ? ugcIntroController
      : pugvIntroController;
  late final UgcIntroController ugcIntroController;
  late final PugvIntroController pugvIntroController;
  late final LocalIntroController localIntroController;

  bool get autoExitFullscreen =>
      videoDetailController.plPlayerController.autoExitFullscreen;

  bool get autoPlayEnable =>
      videoDetailController.plPlayerController.autoPlayEnable;

  bool get enableVerticalExpand =>
      videoDetailController.plPlayerController.enableVerticalExpand;

  bool get pipNoDanmaku =>
      videoDetailController.plPlayerController.pipNoDanmaku;

  bool isShowing = true;

  bool get isFullScreen =>
      videoDetailController.plPlayerController.isFullScreen.value;

  final videoReplyPanelKey = GlobalKey();
  final videoRelatedKey = GlobalKey();
  final videoIntroKey = GlobalKey();

  @override
  void initState() {
    super.initState();

    PlPlayerController.setPlayCallBack(playCallBack);
    videoDetailController = Get.put(VideoDetailController(), tag: heroTag);

    if (videoDetailController.removeSafeArea) {
      hideSystemBar();
    }

    if (videoDetailController.showReply) {
      _videoReplyController = Get.put(
        VideoReplyController(
          aid: videoDetailController.aid,
          videoType: videoDetailController.videoType,
          heroTag: heroTag,
        ),
        tag: heroTag,
      );
    }

    if (videoDetailController.isFileSource) {
      localIntroController = Get.put(LocalIntroController(), tag: heroTag);
    } else if (videoDetailController.isUgc) {
      ugcIntroController = Get.put(UgcIntroController(), tag: heroTag);
    } else {
      pugvIntroController = Get.put(PugvIntroController(), tag: heroTag);
    }

    videoSourceInit();

    addObserverMobile(this);
  }

  // 获取视频资源，初始化播放器
  void videoSourceInit() {
    videoDetailController.queryVideoUrl(autoFullScreenFlag: true);
    if (videoDetailController.autoPlay) {
      plPlayerController = videoDetailController.plPlayerController;
      plPlayerController!
        ..addStatusLister(playerListener)
        ..addPositionListener(positionListener);
    }
  }

  void positionListener(Duration position) {
    videoDetailController.playedTime = position;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final isResume = state == .resumed;
    final ctr = videoDetailController.plPlayerController..visible = isResume;
    if (isResume) {
      if (!ctr.showDanmaku) {
        introController.startTimer();
        ctr.showDanmaku = true;
      }
    } else if (state == .paused) {
      introController.cancelTimer();
      ctr.showDanmaku = false;
    }
  }

  Future<void>? playCallBack() {
    if (!isShowing) {
      plPlayerController
        ?..addStatusLister(playerListener)
        ..addPositionListener(positionListener);
    }
    return plPlayerController?.play();
  }

  // 播放器状态监听
  Future<void> playerListener(PlayerStatus status) async {
    final isPlaying = status.isPlaying;
    try {
      if (videoDetailController.scrollCtr.hasClients) {
        if (isPlaying) {
          if (!videoDetailController.isExpanding &&
              videoDetailController.scrollCtr.offset != 0 &&
              !videoDetailController.animationController.isAnimating) {
            videoDetailController.isExpanding = true;
            videoDetailController.animationController.forward(
              from:
                  1 -
                  videoDetailController.scrollCtr.offset /
                      videoDetailController.videoHeight,
            );
          } else {
            videoDetailController.refreshPage();
          }
        } else {
          videoDetailController.refreshPage();
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('handle player status: $e');
    }

    if (status.isCompleted) {
      try {
        if (videoDetailController
                .steinEdgeInfo
                ?.edges
                ?.questions
                ?.firstOrNull
                ?.choices
                ?.isNotEmpty ==
            true) {
          videoDetailController.showSteinEdgeInfo.value = true;
          return;
        }
      } catch (_) {}

      bool exitFlag = true;

      /// 顺序播放 列表循环
      if (shutdownTimerService.isWaiting) {
        shutdownTimerService.handleWaiting();
      } else {
        switch (plPlayerController!.playRepeat) {
          case PlayRepeat.singleCycle:
            exitFlag = false;
            plPlayerController!.play(repeat: true);
          case PlayRepeat.listOrder:
          case PlayRepeat.listCycle:
          case PlayRepeat.autoPlayRelated:
            exitFlag = !introController.nextPlay();
          case PlayRepeat.pause:
        }
      }

      if (exitFlag) {
        if (autoExitFullscreen) {
          plPlayerController!.triggerFullScreen(status: false);
          if (plPlayerController!.controlsLock.value) {
            plPlayerController!.onLockControl(false);
          }
        } else {
          if (plPlayerController!.controlsLock.value) {
            plPlayerController!.onLockControl(false);
          }
        }
      }
    }
  }

  // 继续播放或重新播放
  void continuePlay() {
    plPlayerController!.play();
  }

  /// 未开启自动播放时触发播放
  Future<void>? handlePlay() {
    if (!videoDetailController.isFileSource) {
      if (videoDetailController.isQuerying) {
        if (kDebugMode) debugPrint('handlePlay: querying');
        return null;
      }
      if (videoDetailController.videoUrl == null ||
          videoDetailController.audioUrl == null) {
        if (kDebugMode) {
          debugPrint('handlePlay: videoUrl/audioUrl not initialized');
        }
        videoDetailController.queryVideoUrl();
        return null;
      }
    }
    final plPlayerController = this.plPlayerController =
        videoDetailController.plPlayerController;
    videoDetailController.autoPlay = true;
    plPlayerController
      ..addStatusLister(playerListener)
      ..addPositionListener(positionListener);
    if (plPlayerController.preInitPlayer) {
      if (plPlayerController.autoEnterFullScreen) {
        plPlayerController.triggerFullScreen();
      }
      return plPlayerController.play();
    } else {
      return videoDetailController.playerInit(
        autoplay: true,
        autoFullScreenFlag: true,
      );
    }
  }

  @override
  void dispose() {
    plPlayerController
      ?..removeStatusLister(playerListener)
      ..removePositionListener(positionListener);

    if (!videoDetailController.isFileSource) {
      if (videoDetailController.isUgc) {
        ugcIntroController
          ..cancelTimer()
          ..videoDetail.close();
      } else {
        pugvIntroController.cancelTimer();
      }
    }

    if (!videoDetailController.removeSafeArea) {
      showSystemBar();
    }

    if (!videoDetailController.plPlayerController.isCloseAll) {
      videoPlayerServiceHandler?.onVideoDetailDispose(heroTag);
      if (plPlayerController != null) {
        videoDetailController.makeHeartBeat();
        plPlayerController!.dispose();
      } else {
        PlPlayerController.updatePlayCount();
      }
    }
    removeObserverMobile(this);

    super.dispose();
  }

  @override
  // 离开当前页面时
  void didPushNext() {
    super.didPushNext();
    isShowing = false;

    removeObserverMobile(this);

    introController.cancelTimer();

    videoDetailController
      ..videoState.value = false
      ..cancelBlockListener()
      ..playerStatus = plPlayerController?.playerStatus.value
      ..brightness = plPlayerController?.brightness.value;
    if (plPlayerController != null) {
      videoDetailController.makeHeartBeat();
      plPlayerController!
        ..removeStatusLister(playerListener)
        ..removePositionListener(positionListener)
        ..pause();
    }
  }

  @override
  // 返回当前页面时
  void didPopNext() {
    super.didPopNext();

    if (videoDetailController.plPlayerController.isCloseAll) {
      return;
    }

    isShowing = true;

    addObserverMobile(this);

    if (videoDetailController.plPlayerController.playerStatus.isPlaying &&
        videoDetailController.playerStatus != PlayerStatus.playing) {
      videoDetailController.plPlayerController.pause();
    }

    PlPlayerController.setPlayCallBack(playCallBack);

    introController.startTimer();

    plPlayerController
      ?..addStatusLister(playerListener)
      ..addPositionListener(positionListener);
    if (videoDetailController.autoPlay) {
      videoDetailController.playerInit(
        autoplay: videoDetailController.playerStatus?.isPlaying ?? false,
      );
    } else if (videoDetailController.plPlayerController.preInitPlayer &&
        !videoDetailController.isQuerying &&
        videoDetailController.videoUrl != null) {
      videoDetailController.playerInit();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (videoDetailController.removeSafeArea) {
      padding = .zero;
    } else {
      padding = MediaQuery.viewPaddingOf(context);
    }

    final size = MediaQuery.sizeOf(context);
    maxWidth = size.width;
    maxHeight = size.height;
    videoDetailController.plPlayerController.screenRatio = maxHeight / maxWidth;

    final shortestSide = size.shortestSide;
    final minVideoHeight = shortestSide / Style.aspectRatio16x9;
    final maxVideoHeight = max(size.longestSide * 0.65, shortestSide);
    videoDetailController
      ..isPortrait = isPortrait = maxHeight >= maxWidth
      ..minVideoHeight = minVideoHeight
      ..maxVideoHeight = maxVideoHeight
      ..videoHeight = videoDetailController.isVertical.value
          ? maxVideoHeight
          : minVideoHeight;

    themeData = videoDetailController.plPlayerController.darkVideoPage
        ? ThemeUtils.darkTheme
        : Theme.of(context);
  }

  Widget get childWhenDisabled {
    return Obx(
      () {
        final isFullScreen = this.isFullScreen;
        return Scaffold(
          resizeToAvoidBottomInset: false,
          appBar: videoDetailController.removeSafeArea
              ? null
              : PreferredSize(
                  preferredSize: const Size.fromHeight(0),
                  child: Obx(
                    () {
                      final scrollRatio =
                          videoDetailController.scrollRatio.value;
                      return AppBar(
                        toolbarHeight: 0,
                        backgroundColor: isPortrait && scrollRatio > 0
                            ? Color.lerp(
                                Colors.black,
                                themeData.colorScheme.surface,
                                scrollRatio,
                              )
                            : Colors.black,
                      );
                    },
                  ),
                ),
          body: ExtendedNestedScrollView(
            key: videoDetailController.scrollKey,
            controller: videoDetailController.scrollCtr,
            onlyOneScrollInBody: true,
            pinnedHeaderSliverHeightBuilder: () {
              double pinnedHeight = this.isFullScreen || !isPortrait
                  ? maxHeight - padding.top
                  : videoDetailController.isExpanding ||
                        videoDetailController.isCollapsing
                  ? videoDetailController.animHeight
                  : videoDetailController.isCollapsing ||
                        (plPlayerController?.playerStatus.isPlaying ?? false)
                  ? videoDetailController.minVideoHeight
                  : kToolbarHeight;
              if (videoDetailController.isExpanding &&
                  videoDetailController.animationController.value == 1) {
                videoDetailController.isExpanding = false;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  videoDetailController.scrollRatio.value = 0;
                  videoDetailController.refreshPage();
                });
              } else if (videoDetailController.isCollapsing &&
                  videoDetailController.animationController.value == 1) {
                videoDetailController.isCollapsing = false;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  videoDetailController.refreshPage();
                });
              }
              return pinnedHeight;
            },
            headerSliverBuilder: (context, innerBoxIsScrolled) {
              final height = isFullScreen || !isPortrait
                  ? maxHeight - padding.top
                  : videoDetailController.isExpanding ||
                        videoDetailController.isCollapsing
                  ? videoDetailController.animHeight
                  : videoDetailController.videoHeight;
              return [
                VideoHeader(
                  minExtent: kToolbarHeight,
                  maxExtent: height,
                  minVideoHeight: videoDetailController.minVideoHeight,
                  onScrollRatioChanged: videoDetailController.scrollRatio.call,
                  child: Stack(
                    clipBehavior: .none,
                    children: [
                      SizedBox(
                        width: maxWidth,
                        height: height,
                        child: videoPlayer(width: maxWidth, height: height),
                      ),
                      _buildHeaderOverlay(),
                    ],
                  ),
                ),
              ];
            },
            body: Scaffold(
              key: videoDetailController.childKey,
              resizeToAvoidBottomInset: false,
              backgroundColor: Colors.transparent,
              body: Column(
                children: [
                  buildTabBar(onTap: videoDetailController.animToTop),
                  Expanded(
                    child: tabBarView(
                      controller: videoDetailController.tabCtr,
                      children: [
                        videoIntro(
                          isHorizontal: false,
                          needCtr: false,
                          isNested: true,
                        ),
                        if (videoDetailController.showReply)
                          videoReplyPanel(isNested: true),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildOverlayToolBar(double scrollRatio) {
    final IconData icon;
    final String playStat;
    if (videoDetailController.playedTime == null) {
      icon = Icons.play_arrow_rounded;
      playStat = '立即';
    } else if (plPlayerController!.isCompleted) {
      icon = CustomIcons.replay_rounded;
      playStat = '重新';
    } else {
      icon = Icons.play_arrow_rounded;
      playStat = '继续';
    }
    final playBtn = Row(
      spacing: 2,
      mainAxisSize: .min,
      children: [
        Icon(icon, color: themeData.colorScheme.primary),
        Text(
          '$playStat播放',
          style: TextStyle(color: themeData.colorScheme.primary),
        ),
      ],
    );
    return Opacity(
      opacity: videoDetailController.scrollRatio.value,
      child: Container(
        color: themeData.colorScheme.surface,
        alignment: .topCenter,
        child: SizedBox(
          height: kToolbarHeight,
          child: Stack(
            clipBehavior: .none,
            children: [
              Align(
                alignment: .centerLeft,
                child: Row(
                  mainAxisSize: .min,
                  children: [
                    SizedBox(
                      width: 42,
                      height: 34,
                      child: IconButton(
                        tooltip: '返回',
                        icon: Icon(
                          FontAwesomeIcons.arrowLeft,
                          size: 15,
                          color: themeData.colorScheme.onSurface,
                        ),
                        onPressed: Get.back,
                      ),
                    ),
                    SizedBox(
                      width: 42,
                      height: 34,
                      child: IconButton(
                        tooltip: '返回主页',
                        icon: Icon(
                          FontAwesomeIcons.house,
                          size: 15,
                          color: themeData.colorScheme.onSurface,
                        ),
                        onPressed:
                            videoDetailController.plPlayerController.onCloseAll,
                      ),
                    ),
                  ],
                ),
              ),
              Center(child: playBtn),
              Align(
                alignment: .centerRight,
                child: videoDetailController.playedTime == null
                    ? _moreBtn(themeData.colorScheme.onSurface)
                    : SizedBox(
                        width: 42,
                        height: 34,
                        child: IconButton(
                          tooltip: "更多设置",
                          style: const ButtonStyle(
                            padding: WidgetStatePropertyAll(EdgeInsets.zero),
                          ),
                          onPressed: () =>
                              (videoDetailController.headerCtrKey.currentState
                                      as HeaderControlState?)
                                  ?.showSettingSheet(),
                          icon: Icon(
                            Icons.more_vert_outlined,
                            size: 19,
                            color: themeData.colorScheme.onSurface,
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderOverlay() {
    return Obx(
      () {
        final scrollRatio = videoDetailController.scrollRatio.value;
        if (scrollRatio == 0) {
          return const SizedBox.shrink();
        }
        return Positioned.fill(
          bottom: -2,
          child: GestureDetector(
            onTap: () {
              if (!videoDetailController.isFileSource) {
                if (videoDetailController.isQuerying) {
                  if (kDebugMode) {
                    debugPrint('handlePlay: querying');
                  }
                  return;
                }
                if (videoDetailController.videoUrl == null ||
                    videoDetailController.audioUrl == null) {
                  if (kDebugMode) {
                    debugPrint('handlePlay: videoUrl/audioUrl not initialized');
                  }
                  videoDetailController.queryVideoUrl();
                  return;
                }
              }
              if (plPlayerController == null ||
                  videoDetailController.playedTime == null) {
                handlePlay();
              } else {
                plPlayerController!.onDoubleTapCenter();
              }
            },
            behavior: .opaque,
            child: _buildOverlayToolBar(scrollRatio),
          ),
        );
      },
    );
  }

  Widget get manualPlayerWidget => Obx(() {
    if (!videoDetailController.autoPlay) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AppBar(
              primary: false,
              elevation: 0,
              scrolledUnderElevation: 0,
              foregroundColor: Colors.white,
              backgroundColor: Colors.transparent,
              automaticallyImplyLeading: false,
              title: Row(
                children: [
                  SizedBox(
                    width: 42,
                    height: 34,
                    child: IconButton(
                      tooltip: '返回',
                      icon: const Icon(
                        FontAwesomeIcons.arrowLeft,
                        size: 15,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            blurRadius: 1.5,
                            color: Colors.black,
                          ),
                        ],
                      ),
                      onPressed: Get.back,
                    ),
                  ),
                  SizedBox(
                    width: 42,
                    height: 34,
                    child: IconButton(
                      tooltip: '返回主页',
                      icon: const Icon(
                        FontAwesomeIcons.house,
                        size: 15,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            blurRadius: 1.5,
                            color: Colors.black,
                          ),
                        ],
                      ),
                      onPressed:
                          videoDetailController.plPlayerController.onCloseAll,
                    ),
                  ),
                ],
              ),
              actions: [
                _moreBtn(
                  Colors.white,
                  shadows: const [
                    Shadow(
                      blurRadius: 1.5,
                      color: Colors.black,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            right: 12,
            bottom: 10,
            child: IconButton(
              tooltip: '播放',
              onPressed: handlePlay,
              icon: const PlayIcon(),
            ),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  });

  Widget _moreBtn(Color color, {List<Shadow>? shadows}) => PopupMenuButton(
    icon: Icon(
      size: 22,
      Icons.more_vert,
      color: color,
      shadows: shadows,
    ),
    itemBuilder: (BuildContext context) => <PopupMenuEntry>[
      PopupMenuItem(
        onTap: introController.viewLater,
        child: const Text('稍后再看'),
      ),
      if (videoDetailController.epId == null)
        PopupMenuItem(
          onTap: () => videoDetailController.showNoteList(context),
          child: const Text('查看笔记'),
        ),
      if (!videoDetailController.isFileSource)
        PopupMenuItem(
          onTap: () => videoDetailController.onDownload(this.context),
          child: const Text('缓存视频'),
        ),
      if (videoDetailController.cover.value.isNotEmpty)
        PopupMenuItem(
          onTap: () =>
              ImageUtils.downloadImg([videoDetailController.cover.value]),
          child: const Text('保存封面'),
        ),
      if (!videoDetailController.isFileSource && videoDetailController.isUgc)
        PopupMenuItem(
          onTap: videoDetailController.toAudioPage,
          child: const Text('听音频'),
        ),
    ],
  );

  Widget plPlayer({
    required double width,
    required double height,
    bool isPipMode = false,
  }) => popScope(
    key: videoDetailController.videoPlayerKey,
    canPop:
        !isFullScreen &&
        !videoDetailController.plPlayerController.isDesktopPip &&
        isPortrait,
    onPopInvokedWithResult:
        videoDetailController.plPlayerController.onPopInvokedWithResult,
    child: Obx(
      () =>
          !videoDetailController.videoState.value ||
              !videoDetailController.autoPlay ||
              plPlayerController?.videoController == null
          ? const SizedBox.shrink()
          : PLVideoPlayer(
              maxWidth: width,
              maxHeight: height,
              plPlayerController: plPlayerController!,
              videoDetailController: videoDetailController,
              introController: introController,
              headerControl: HeaderControl(
                key: videoDetailController.headerCtrKey,
                isPortrait: isPortrait,
                controller: videoDetailController.plPlayerController,
                videoDetailCtr: videoDetailController,
                heroTag: heroTag,
              ),
              danmuWidget: isPipMode && pipNoDanmaku
                  ? null
                  : Obx(
                      () => PlDanmaku(
                        key: ValueKey(videoDetailController.cid.value),
                        isPipMode: isPipMode,
                        cid: videoDetailController.cid.value,
                        playerController: plPlayerController!,
                        isFullScreen: plPlayerController!.isFullScreen.value,
                        isFileSource: videoDetailController.isFileSource,
                        size: Size(width, height),
                      ),
                    ),
              showEpisodes: showEpisodes,
              showViewPoints: showViewPoints,
            ),
    ),
  );

  late ThemeData themeData;
  late bool isPortrait;
  late double maxWidth;
  late double maxHeight;
  late EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (videoDetailController.plPlayerController.isPipMode) {
      child = plPlayer(width: maxWidth, height: maxHeight, isPipMode: true);
    } else {
      child = childWhenDisabled;
    }
    if (videoDetailController.plPlayerController.keyboardControl) {
      child = PlayerFocus(
        plPlayerController: videoDetailController.plPlayerController,
        introController: introController,
        onSendDanmaku: videoDetailController.showShootDanmakuSheet,
        canPlay: () {
          if (videoDetailController.autoPlay) {
            return true;
          }
          handlePlay();
          return false;
        },
        onSkipSegment: videoDetailController.onSkipSegment,
        child: child,
      );
    }
    return videoDetailController.plPlayerController.darkVideoPage
        ? Theme(data: themeData, child: child)
        : child;
  }

  Widget buildTabBar({
    bool needIndicator = true,
    String? introText,
    bool showIntro = true,
    VoidCallback? onTap,
  }) {
    List<String> tabs = [
      if (showIntro)
        videoDetailController.isFileSource ? '离线视频' : introText ?? '简介',
      if (videoDetailController.showReply) '评论',
    ];
    if (videoDetailController.tabCtr.length != tabs.length) {
      videoDetailController.tabCtr.dispose();
      videoDetailController.tabCtr = TabController(
        vsync: videoDetailController,
        length: tabs.length,
        initialIndex: tabs.isEmpty
            ? 0
            : videoDetailController.tabCtr.index.clamp(0, tabs.length - 1),
      );
    }

    final flag = !needIndicator || tabs.length == 1;
    Widget tabBar() => TabBar(
      labelColor: flag ? themeData.colorScheme.onSurface : null,
      indicator: flag ? const BoxDecoration() : null,
      padding: EdgeInsets.zero,
      controller: videoDetailController.tabCtr,
      labelStyle:
          TabBarTheme.of(context).labelStyle?.copyWith(fontSize: 13) ??
          const TextStyle(fontSize: 13),
      labelPadding: const EdgeInsets.symmetric(horizontal: 10.0),
      dividerColor: Colors.transparent,
      dividerHeight: 0,
      onTap: (value) {
        void animToTop() {
          if (onTap != null) {
            onTap();
            return;
          }
          String text = tabs[value];
          if (videoDetailController.isFileSource ||
              text == '简介' ||
              text == '相关视频') {
            videoDetailController.introScrollCtr?.animToTop();
          } else if (text.startsWith('评论')) {
            _videoReplyController.animateToTop();
          }
        }

        if (flag) {
          animToTop();
        } else if (!videoDetailController.tabCtr.indexIsChanging) {
          animToTop();
        }
      },
      tabs: tabs.map((text) {
        if (text == '评论') {
          return Obx(() {
            final count = _videoReplyController.count.value;
            return Tab(
              text: '评论${count == -1 ? '' : ' ${NumUtils.numFormat(count)}'}',
            );
          });
        } else {
          return Tab(text: text);
        }
      }).toList(),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: themeData.dividerColor.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: SizedBox(
        height: 45,
        child: Row(
          children: [
            if (tabs.isEmpty)
              const Spacer()
            else
              Flexible(
                flex: tabs.length == 3 ? 2 : 1,
                child: tabBar(),
              ),
            Flexible(
              flex: 1,
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SizedBox(
                      height: 32,
                      child: TextButton(
                        style: const ButtonStyle(
                          padding: WidgetStatePropertyAll(EdgeInsets.zero),
                        ),
                        onPressed: videoDetailController.showShootDanmakuSheet,
                        child: Text(
                          '发弹幕',
                          style: TextStyle(
                            fontSize: 12,
                            color: themeData.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 38,
                      height: 38,
                      child: Obx(
                        () {
                          final ctr = videoDetailController.plPlayerController;
                          final enableShowDanmaku = ctr.enableShowDanmaku.value;
                          return IconButton(
                            onPressed: () {
                              final newVal = !enableShowDanmaku;
                              ctr.enableShowDanmaku.value = newVal;
                              if (!ctr.tempPlayerConf) {
                                GStorage.setting.put(
                                  SettingBoxKey.enableShowDanmaku,
                                  newVal,
                                );
                              }
                            },
                            icon: Icon(
                              size: 22,
                              enableShowDanmaku
                                  ? CustomIcons.dm_on
                                  : CustomIcons.dm_off,
                              color: enableShowDanmaku
                                  ? themeData.colorScheme.secondary
                                  : themeData.colorScheme.outline,
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 14),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget videoPlayer({required double width, required double height}) {
    final isFullScreen = this.isFullScreen;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        const Positioned.fill(child: ColoredBox(color: Colors.black)),

        plPlayer(width: width, height: height),

        Obx(() {
          if (!videoDetailController.autoPlay) {
            return Positioned.fill(
              bottom: -1,
              child: GestureDetector(
                onTap: handlePlay,
                behavior: .opaque,
                child: Obx(
                  () => NetworkImgLayer(
                    type: .emote,
                    quality: 60,
                    src: videoDetailController.cover.value,
                    width: width,
                    height: height,
                    cacheWidth: true,
                    getPlaceHolder: () => Center(
                      child: Image.asset(Assets.loading),
                    ),
                  ),
                ),
              ),
            );
          }
          return const SizedBox.shrink();
        }),
        manualPlayerWidget,

        if (videoDetailController.plPlayerController.enableSponsorBlock ||
            videoDetailController.continuePlayingPart)
          Positioned(
            left: 16,
            bottom: isFullScreen ? max(75, maxHeight * 0.25) : 75,
            width: MediaQuery.textScalerOf(context).scale(120),
            child: AnimatedList(
              padding: EdgeInsets.zero,
              key: videoDetailController.listKey,
              reverse: true,
              shrinkWrap: true,
              initialItemCount: videoDetailController.listData.length,
              itemBuilder: (context, index, animation) {
                return videoDetailController.buildItem(
                  videoDetailController.listData[index],
                  animation,
                );
              },
            ),
          ),

        // for debug
        // Positioned(
        //   right: 16,
        //   bottom: 75,
        //   child: FilledButton.tonal(
        //     onPressed: () {
        //       videoDetailController.onAddItem(
        //         SegmentModel(
        //           UUID: '',
        //           segmentType:
        //               SegmentType.values[Utils.random.nextInt(
        //                 SegmentType.values.length,
        //               )],
        //           segment: Pair(first: 0, second: 0),
        //           skipType: SkipType.alwaysSkip,
        //         ),
        //       );
        //     },
        //     child: const Text('skip'),
        //   ),
        // ),
        // Positioned(
        //   right: 16,
        //   bottom: 120,
        //   child: FilledButton.tonal(
        //     onPressed: () {
        //       videoDetailController.onAddItem(2);
        //     },
        //     child: const Text('index'),
        //   ),
        // ),
        Obx(
          () {
            if (videoDetailController.showSteinEdgeInfo.value) {
              try {
                return Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: 16,
                      right: 16,
                      bottom: plPlayerController?.showControls.value == true
                          ? 75
                          : 16,
                    ),
                    child: Wrap(
                      spacing: 25,
                      runSpacing: 10,
                      children: videoDetailController
                          .steinEdgeInfo!
                          .edges!
                          .questions!
                          .first
                          .choices!
                          .map((item) {
                            return FilledButton.tonal(
                              style: FilledButton.styleFrom(
                                shape: const RoundedRectangleBorder(
                                  borderRadius: .all(.circular(6)),
                                ),
                                backgroundColor: themeData
                                    .colorScheme
                                    .secondaryContainer
                                    .withValues(alpha: 0.8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 15,
                                  vertical: 10,
                                ),
                                visualDensity: VisualDensity.compact,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: () {
                                ugcIntroController.onChangeEpisode(
                                  item,
                                  isStein: true,
                                );
                                videoDetailController.getSteinEdgeInfo(item.id);
                              },
                              child: Text(item.option!),
                            );
                          })
                          .toList(),
                    ),
                  ),
                );
              } catch (e) {
                if (kDebugMode) debugPrint('build stein edges: $e');
                return const SizedBox.shrink();
              }
            }
            return const SizedBox.shrink();
          },
        ),
      ],
    );
  }

  Widget localIntroPanel({
    bool needCtr = true,
  }) {
    return CustomScrollView(
      controller: needCtr
          ? videoDetailController.effectiveIntroScrollCtr
          : null,
      physics: !needCtr
          ? const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics())
          : null,
      key: const PageStorageKey(CommonIntroController),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.only(top: 7, bottom: padding.bottom + 100),
          sliver: LocalIntroPanel(
            key: videoRelatedKey,
            heroTag: heroTag,
          ),
        ),
      ],
    );
  }

  Widget videoIntro({
    double? width,
    double? height,
    bool? isHorizontal,
    bool needRelated = true,
    bool needCtr = true,
    bool isNested = false,
  }) {
    if (videoDetailController.isFileSource) {
      return localIntroPanel(needCtr: needCtr);
    }
    Widget introPanel() {
      Widget child = CustomScrollView(
        key: const PageStorageKey(CommonIntroController),
        controller: needCtr
            ? videoDetailController.effectiveIntroScrollCtr
            : null,
        physics: !needCtr
            ? const AlwaysScrollableScrollPhysics(
                parent: ClampingScrollPhysics(),
              )
            : null,
        slivers: [
          if (videoDetailController.isUgc) ...[
            UgcIntroPanel(
              key: videoIntroKey,
              heroTag: heroTag,
              showAiBottomSheet: showAiBottomSheet,
              showEpisodes: showEpisodes,
              isPortrait: isPortrait,
              isHorizontal: isHorizontal ?? width! / height! >= kScreenRatio,
            ),
            if (needRelated && videoDetailController.showRelatedVideo) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(
                    top: Style.safeSpace,
                  ),
                  child: Divider(
                    height: 1,
                    indent: 12,
                    endIndent: 12,
                    color: themeData.colorScheme.outline.withValues(
                      alpha: 0.08,
                    ),
                  ),
                ),
              ),
              RelatedVideoPanel(key: videoRelatedKey, heroTag: heroTag),
            ],
          ] else
            PugvIntroPage(
              key: videoIntroKey,
              heroTag: heroTag,
              cid: videoDetailController.cid.value,
              showEpisodes: showEpisodes,
              maxWidth: width ?? maxWidth,
            ),
          SliverToBoxAdapter(
            child: SizedBox(
              height:
                  (videoDetailController.isPlayAll && !isPortrait
                      ? 80
                      : Style.safeSpace) +
                  padding.bottom,
            ),
          ),
        ],
      );
      if (isNested) {
        child = ExtendedVisibilityDetector(
          uniqueKey: const Key('intro-panel'),
          child: child,
        );
      }
      return KeepAliveWrapper(child: child);
    }

    if (videoDetailController.isPlayAll) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          introPanel(),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12 + padding.bottom,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: () => videoDetailController.showMediaListPanel(context),
                borderRadius: const BorderRadius.all(Radius.circular(14)),
                child: Container(
                  height: 54,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: themeData.colorScheme.secondaryContainer.withValues(
                      alpha: 0.95,
                    ),
                    borderRadius: const BorderRadius.all(Radius.circular(14)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.playlist_play, size: 24),
                      const SizedBox(width: 10),
                      Text(
                        videoDetailController.watchLaterTitle,
                        style: TextStyle(
                          color: themeData.colorScheme.onSecondaryContainer,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const Spacer(),
                      const Icon(Icons.keyboard_arrow_up_rounded, size: 26),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }
    return introPanel();
  }

  Widget videoReplyPanel({bool isNested = false}) => VideoReplyPanel(
    key: videoReplyPanelKey,
    isNested: isNested,
    heroTag: heroTag,
  );

  // ai总结
  void showAiBottomSheet() {
    videoDetailController.childKey.currentState?.showBottomSheet(
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(),
      (context) =>
          AiConclusionPanel(item: ugcIntroController.aiConclusionResult!),
    );
  }

  void showEpisodes([
    int? index,
    UgcSeason? season,
    List<ugc.BaseEpisodeItem>? episodes,
    String? bvid,
    int? aid,
    int? cid,
  ]) {
    assert((cid == null) == (bvid == null));
    final isFullScreen = this.isFullScreen;
    if (cid == null) {
      videoDetailController.showMediaListPanel(context);
      return;
    }
    Widget listSheetContent({bool enableSlide = true}) => EpisodePanel(
      heroTag: heroTag,
      ugcIntroController: videoDetailController.isUgc
          ? ugcIntroController
          : null,
      type: season != null
          ? EpisodeType.season
          : episodes is List<Part>
          ? EpisodeType.part
          : EpisodeType.pugv,
      cover: videoDetailController.cover.value,
      enableSlide: enableSlide,
      initialTabIndex: index ?? 0,
      bvid: bvid!,
      aid: aid,
      cid: cid,
      seasonId: season?.id,
      list: season != null ? season.sections! : [episodes],
      isReversed: !videoDetailController.isUgc
          ? null
          : season != null
          ? ugcIntroController
                .videoDetail
                .value
                .ugcSeason!
                .sections![videoDetailController.seasonIndex.value]
                .isReversed
          : ugcIntroController.videoDetail.value.isPageReversed,
      isSupportReverse: videoDetailController.isUgc,
      onChangeEpisode: videoDetailController.isUgc
          ? ugcIntroController.onChangeEpisode
          : pugvIntroController.onChangeEpisode,
      onClose: Get.back,
      onReverse: () {
        Get.back();
        onReversePlay(isSeason: season != null);
      },
    );
    if (isFullScreen || videoDetailController.showVideoSheet) {
      final child = listSheetContent(enableSlide: false);
      PageUtils.showVideoBottomSheet(
        context,
        child: videoDetailController.plPlayerController.darkVideoPage
            ? Theme(data: themeData, child: child)
            : child,
      );
    } else {
      videoDetailController.childKey.currentState?.showBottomSheet(
        backgroundColor: Colors.transparent,
        constraints: const BoxConstraints(),
        (context) => listSheetContent(),
      );
    }
  }

  void onReversePlay({required bool isSeason}) {
    if (isSeason && videoDetailController.isPlayAll) {
      SmartDialog.showToast('当前为播放全部，合集不支持倒序');
      return;
    }

    final videoDetail = ugcIntroController.videoDetail.value;
    if (isSeason) {
      // reverse season
      final item = videoDetail
          .ugcSeason!
          .sections![videoDetailController.seasonIndex.value];
      item
        ..isReversed = !item.isReversed
        ..episodes = item.episodes!.reversed.toList();

      if (!videoDetailController.plPlayerController.reverseFromFirst) {
        // keep current episode
        videoDetailController
          ..seasonIndex.refresh()
          ..cid.refresh();
      } else {
        // switch to first episode
        final episode = ugcIntroController
            .videoDetail
            .value
            .ugcSeason!
            .sections![videoDetailController.seasonIndex.value]
            .episodes!
            .first;
        if (episode.cid != videoDetailController.cid.value) {
          ugcIntroController.onChangeEpisode(episode);
          videoDetailController.seasonCid = episode.cid;
        } else {
          videoDetailController
            ..seasonIndex.refresh()
            ..cid.refresh();
        }
      }
    } else {
      // reverse part
      videoDetail
        ..isPageReversed = !videoDetail.isPageReversed
        ..pages = videoDetail.pages!.reversed.toList();
      if (!videoDetailController.plPlayerController.reverseFromFirst) {
        // keep current episode
        videoDetailController.cid.refresh();
      } else {
        // switch to first episode
        final episode = videoDetail.pages!.first;
        if (episode.cid != videoDetailController.cid.value) {
          ugcIntroController.onChangeEpisode(episode);
        } else {
          videoDetailController.cid.refresh();
        }
      }
    }
  }

  void showViewPoints() {
    if (isFullScreen || videoDetailController.showVideoSheet) {
      final child = ViewPointsPage(
        enableSlide: false,
        videoDetailController: videoDetailController,
        plPlayerController: plPlayerController,
      );
      PageUtils.showVideoBottomSheet(
        context,
        child: videoDetailController.plPlayerController.darkVideoPage
            ? Theme(data: themeData, child: child)
            : child,
      );
    } else {
      videoDetailController.childKey.currentState?.showBottomSheet(
        backgroundColor: Colors.transparent,
        constraints: const BoxConstraints(),
        (context) => ViewPointsPage(
          videoDetailController: videoDetailController,
          plPlayerController: plPlayerController,
        ),
      );
    }
  }
}
