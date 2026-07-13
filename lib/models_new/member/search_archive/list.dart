import 'package:PiliPlus/models_new/member/search_archive/slist.dart';
import 'package:PiliPlus/models_new/member/search_archive/vlist.dart';

class SearchArchiveList {
  List<ListTag>? tags;
  List<VListItemModel>? vlist;

  SearchArchiveList.fromJson(Map<String, dynamic> json) {
    vlist = (json['vlist'] as List<dynamic>?)
        ?.where(
          (e) =>
              e['is_lesson_video'] == 1 ||
              e['jump_url'] == null ||
              e['jump_url'] == '',
        )
        .map((e) => VListItemModel.fromJson(e as Map<String, dynamic>))
        .toList();
    tags = (json['slist'] as List<dynamic>?)
        ?.map((e) => ListTag.fromJson(e as Map<String, dynamic>))
        .toList();
    (json['tlist'] as Map<String, dynamic>?)?.forEach((k, v) {
      if (k == '196') {
        if (tags == null) {
          tags = [ListTag.fromJson(v)];
        } else {
          tags!.add(ListTag.fromJson(v));
        }
        return;
      }
    });
  }
}
