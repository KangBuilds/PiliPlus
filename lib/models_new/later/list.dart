import 'package:PiliPlus/models/model_owner.dart';
import 'package:PiliPlus/models_new/later/rights.dart';
import 'package:PiliPlus/models_new/later/stat.dart';
import 'package:PiliPlus/models_new/video/video_detail/dimension.dart';
import 'package:PiliPlus/pages/common/multi_select/base.dart';

class LaterItemModel with MultiSelectData {
  int? aid;
  String? pic;
  String? title;
  int? pubdate;
  int? duration;
  Rights? rights;
  Owner? owner;
  Stat? stat;
  int? cid;
  int? progress;
  String? bvid;
  bool? isPugv;
  bool? isCharging;
  Dimension? dimension;

  LaterItemModel({
    this.aid,
    this.pic,
    this.title,
    this.pubdate,
    this.duration,
    this.rights,
    this.owner,
    this.stat,
    this.cid,
    this.progress,
    this.bvid,
    this.isPugv,
    this.isCharging,
    this.dimension,
  });

  factory LaterItemModel.fromJson(Map<String, dynamic> json) => LaterItemModel(
    aid: json['aid'] as int?,
    pic: json['pic'] as String?,
    title: json['title'] as String?,
    pubdate: json['pubdate'] as int?,
    duration: json['duration'] as int?,
    rights: json['rights'] == null
        ? null
        : Rights.fromJson(json['rights'] as Map<String, dynamic>),
    owner: json['owner'] == null
        ? null
        : Owner.fromJson(json['owner'] as Map<String, dynamic>),
    stat: json['stat'] == null
        ? null
        : Stat.fromJson(json['stat'] as Map<String, dynamic>),
    cid: json['cid'] as int?,
    progress: json['progress'] as int?,
    bvid: json['bvid'] as String?,
    isPugv: json['is_pugv'] as bool?,
    isCharging: json['charging_pay']?['level'] != null,
    dimension: json['dimension'] == null
        ? null
        : Dimension.fromJson(json['dimension'] as Map<String, dynamic>),
  );
}
