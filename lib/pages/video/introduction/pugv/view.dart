import 'dart:math';

import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/button/icon_button.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/image_viewer/hero.dart';
import 'package:PiliPlus/models/common/image_preview_type.dart';
import 'package:PiliPlus/models/common/image_type.dart';
import 'package:PiliPlus/models_new/pugv/season_info/result.dart';
import 'package:PiliPlus/pages/video/controller.dart';
import 'package:PiliPlus/pages/video/introduction/pugv/controller.dart';
import 'package:PiliPlus/pages/video/introduction/pugv/widgets/episode_panel.dart';
import 'package:PiliPlus/utils/extension/get_ext.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class PugvIntroPage extends StatefulWidget {
  const PugvIntroPage({
    super.key,
    this.cid,
    required this.heroTag,
    required this.showEpisodes,
    required this.maxWidth,
  });

  final int? cid;
  final String heroTag;
  final Function showEpisodes;
  final double maxWidth;

  @override
  State<PugvIntroPage> createState() => _PugvIntroPageState();
}

class _PugvIntroPageState extends State<PugvIntroPage> {
  late final PugvIntroController introController;
  late final VideoDetailController videoDetailCtr;

  @override
  void initState() {
    super.initState();
    introController = Get.putOrFind(
      PugvIntroController.new,
      tag: widget.heroTag,
    );
    videoDetailCtr = Get.find<VideoDetailController>(tag: widget.heroTag);
  }

  @override
  Widget build(BuildContext context) {
    final item = introController.seasonItem;
    Widget sliver = SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 10,
            children: [
              _buildCover(ColorScheme.of(context), item),
              Expanded(child: _buildInfoPanel(ColorScheme.of(context), item)),
            ],
          ),
          const SizedBox(height: 6),
          if (item.episodes?.isNotEmpty == true)
            PugvPanel(
              heroTag: widget.heroTag,
              pages: item.episodes!,
              cid: videoDetailCtr.cid.value,
              onChangeEpisode: introController.onChangeEpisode,
              showEpisodes: widget.showEpisodes,
              newEp: item.newEp,
            ),
        ],
      ),
    );
    final brief = _buildBrief(item);
    if (brief != null) {
      sliver = SliverMainAxisGroup(slivers: [sliver, brief]);
    }
    return SliverPadding(
      padding: const .fromLTRB(
        Style.safeSpace,
        Style.safeSpace,
        Style.safeSpace,
        Style.safeSpace + 50,
      ),
      sliver: sliver,
    );
  }

  Widget? _buildBrief(SeasonInfoModel item) {
    final img = item.brief?.img;
    if (img == null || img.isEmpty) {
      return null;
    }
    final maxWidth = widget.maxWidth - 24;
    var padding = max(0.0, maxWidth - 400) / 2;
    final imgWidth = maxWidth - padding * 2;
    return SliverPadding(
      padding: .only(top: 10, left: padding, right: padding),
      sliver: SliverMainAxisGroup(
        slivers: img
            .map(
              (e) => SliverToBoxAdapter(
                child: NetworkImgLayer(
                  type: .emote,
                  src: e.url,
                  width: imgWidth,
                  height: imgWidth * e.aspectRatio,
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildCover(ColorScheme colorScheme, SeasonInfoModel item) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: () => PageUtils.imageView(
            imgList: [SourceModel(url: item.cover!)],
          ),
          child: fromHero(
            tag: item.cover!,
            child: NetworkImgLayer(
              width: 115,
              height: 153,
              src: item.cover!,
            ),
          ),
        ),
        Positioned(
          right: 6,
          bottom: 6,
          child: Obx(() {
            final isFav = introController.isFav.value;
            return iconButton(
              size: 28,
              iconSize: 26,
              tooltip: '${isFav ? '取消' : ''}收藏',
              onPressed: () => introController.onFavPugv(isFav),
              icon: isFav
                  ? const Icon(Icons.star_rounded)
                  : const Icon(Icons.star_border_rounded),
              bgColor: isFav
                  ? colorScheme.secondaryContainer
                  : colorScheme.onInverseSurface,
              iconColor: isFav
                  ? colorScheme.onSecondaryContainer
                  : colorScheme.onSurfaceVariant,
            );
          }),
        ),
      ],
    );
  }

  Widget _buildInfoPanel(ColorScheme colorScheme, SeasonInfoModel item) {
    Widget upInfo(int mid, String avatar, String name, {String? role}) =>
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Get.toNamed('/member?mid=$mid'),
          child: Row(
            spacing: 8,
            mainAxisSize: MainAxisSize.min,
            children: [
              NetworkImgLayer(
                src: avatar,
                width: 35,
                height: 35,
                type: ImageType.avatar,
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name),
                  if (role?.isNotEmpty == true)
                    Text(
                      role!,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.outline,
                      ),
                    ),
                ],
              ),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (item.cooperators?.isNotEmpty == true) ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              spacing: 25,
              children: item.cooperators!
                  .map(
                    (e) => upInfo(
                      e.mid!,
                      e.avatar!,
                      e.nickName!,
                      role: e.role,
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 6),
        ] else if (item.upInfo?.mid != null) ...[
          upInfo(
            item.upInfo!.mid!,
            item.upInfo!.avatar!,
            item.upInfo!.uname!,
          ),
          const SizedBox(height: 6),
        ],
        Text(item.title!, style: const TextStyle(fontSize: 16)),
        if (item.subtitle?.isNotEmpty == true) ...[
          const SizedBox(height: 5),
          Text(
            item.subtitle!,
            style: TextStyle(
              fontSize: 13,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
