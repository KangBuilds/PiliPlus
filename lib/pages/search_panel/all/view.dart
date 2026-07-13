import 'package:PiliPlus/common/skeleton/video_card_h.dart';
import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/video_card/video_card_h.dart';
import 'package:PiliPlus/models/search/result.dart';
import 'package:PiliPlus/pages/search_panel/all/controller.dart';
import 'package:PiliPlus/pages/search_panel/user/widgets/item.dart';
import 'package:PiliPlus/pages/search_panel/view.dart';
import 'package:PiliPlus/utils/grid.dart';
import 'package:PiliPlus/utils/waterfall.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:waterfall_flow/waterfall_flow.dart'
    hide SliverWaterfallFlowDelegateWithMaxCrossAxisExtent;

class SearchAllPanel extends CommonSearchPanel {
  const SearchAllPanel({
    super.key,
    required super.keyword,
    required super.tag,
    required super.searchType,
  });

  @override
  State<SearchAllPanel> createState() => _SearchAllPanelState();
}

class _SearchAllPanelState
    extends CommonSearchPanelState<SearchAllPanel, SearchAllData, dynamic> {
  @override
  late final SearchAllController controller;

  @override
  void initState() {
    super.initState();
    controller = Get.put(
      SearchAllController(
        keyword: widget.keyword,
        searchType: widget.searchType,
        tag: widget.tag,
      ),
      tag: widget.searchType.name + widget.tag,
    );
  }

  @override
  Widget buildList(ThemeData theme, List<dynamic> list) {
    return SliverWaterfallFlow(
      gridDelegate: SliverWaterfallFlowDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: Grid.smallCardWidth * 2,
        crossAxisSpacing: Style.safeSpace,
      ),
      delegate: SliverChildBuilderDelegate(
        (_, index) {
          if (index == list.length - 1) {
            controller.onLoadMore();
          }
          return switch (list[index]) {
            SearchVideoItemModel e => SizedBox(
              height: 120,
              child: VideoCardH(videoItem: e),
            ),
            SearchUserItemModel e => Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: SearchUserItem(item: e),
            ),
            _ => const SizedBox.shrink(),
          };
        },
        childCount: list.length,
      ),
    );
  }

  @override
  Widget get buildLoading => SliverGrid.builder(
    gridDelegate: Grid.videoCardHDelegate(),
    itemBuilder: (context, index) => const VideoCardHSkeleton(),
    itemCount: 10,
  );
}
