import 'package:PiliPlus/models_new/follow/list.dart';
import 'package:PiliPlus/utils/parse_int.dart';

class FollowUpModel {
  List<UpItem>? upList;
  bool? hasMore;
  String? offset;

  void addAllUpList(List<UpItem> newList) {
    if (upList != null) {
      upList!.addAll(newList);
    } else {
      upList = newList;
    }
  }

  factory FollowUpModel.fromJson(Map<String, dynamic> json) {
    return FollowUpModel.fromUpList(json['up_list']);
  }

  FollowUpModel.fromUpList(Map<String, dynamic>? json) {
    if (json != null) {
      upList = (json['items'] as List?)
          ?.map((e) => UpItem.fromJson(e))
          .toList();
      hasMore = json['has_more'];
      offset = json['offset'];
    }
  }

  FollowUpModel.fromFollowList(Map<String, dynamic> json) {
    upList = (json['list'] as List?)
        ?.map((e) => FollowItemModel.fromJson(e))
        .toList();
  }
}

class UpItem {
  String? face;
  bool? hasUpdate;
  late int mid;
  String? uname;

  UpItem({
    this.face,
    this.hasUpdate,
    required this.mid,
    this.uname,
  });

  UpItem.fromJson(Map<String, dynamic> json) {
    face = json['face'];
    hasUpdate = json['has_update'];
    mid = safeToInt(json['mid']) ?? 0;
    uname = json['uname'];
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is UpItem && mid == other.mid;

  @override
  int get hashCode => mid.hashCode;
}
