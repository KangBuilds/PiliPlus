import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/pages/common/common_list_controller.dart';

class ZoneController extends CommonListController {
  ZoneController({this.rid});

  int? rid;

  @override
  void onInit() {
    super.onInit();
    queryData();
  }

  @override
  Future<LoadingState> customGetData() => VideoHttp.getRankVideoList(rid!);
}
