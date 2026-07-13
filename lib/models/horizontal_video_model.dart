import 'package:PiliPlus/models/model_video.dart';
import 'package:PiliPlus/models_new/video/video_detail/dimension.dart';

abstract class HorizontalVideoModel extends BaseVideoItemModel {
  bool? isPugv;
  int? seasonId;

  Dimension? dimension;

  String? badge;

  num? progress;

  // search
  List<({bool isEm, String text})>? titleList;
}
