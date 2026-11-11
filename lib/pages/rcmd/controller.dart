import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/models/common/rcmd_source.dart';
import 'package:PiliPlus/pages/common/common_list_controller.dart';
import 'package:PiliPlus/utils/storage_pref.dart';

class RcmdController extends CommonListController {
  late bool enableSaveLastData = Pref.enableSaveLastData;
  RcmdSource _rcmdSource = Pref.rcmdSource;
  RcmdSource get rcmdSource => _rcmdSource;
  bool get appRcmd => rcmdSource == RcmdSource.app;
  int _sourceVersion = 0;
  bool _resetSource = false;

  int? lastRefreshAt;
  late bool savedRcmdTip = Pref.savedRcmdTip;

  @override
  bool get isEnd => false;

  @override
  void onInit() {
    super.onInit();
    page = 0;
    queryData();
  }

  @override
  Future<LoadingState> customGetData() async {
    while (true) {
      final version = _sourceVersion;
      final result = await switch (rcmdSource) {
        RcmdSource.app => VideoHttp.rcmdVideoListApp(freshIdx: page),
        RcmdSource.web => VideoHttp.rcmdVideoList(freshIdx: page, ps: 20),
        RcmdSource.desktop => VideoHttp.rcmdVideoList(
          freshIdx: page,
          ps: 30,
          desktop: true,
        ),
      };
      // A source switch can happen while a refresh or load-more is in flight.
      if (version == _sourceVersion) {
        if (_resetSource && result is Error) {
          _resetSource = false;
          loadingState.value = result;
        }
        return result;
      }
    }
  }

  void switchSource(RcmdSource source) {
    if (source == rcmdSource) return;
    _rcmdSource = source;
    _sourceVersion++;
    _resetSource = true;
    lastRefreshAt = null;
    onReload();
  }

  @override
  bool customHandleResponse(bool isRefresh, Success response) {
    if (!_resetSource) return false;
    _resetSource = false;
    // Replace the list even if the original request was a load-more.
    loadingState.value = Success(response.response as List?);
    return true;
  }

  @override
  bool handleError(String? errMsg) {
    return enableSaveLastData;
  }

  @override
  void handleListResponse(List dataList) {
    if (enableSaveLastData && page == 0) {
      if (loadingState.value case Success(:final response)) {
        if (response != null && response.isNotEmpty) {
          if (savedRcmdTip) {
            lastRefreshAt = dataList.length;
          }
          if (response.length > 200) {
            dataList.addAll(response.take(50));
          } else {
            dataList.addAll(response);
          }
        }
      }
    }
  }

  @override
  Future<void> onRefresh() {
    page = 0;
    isEnd = false;
    return queryData();
  }
}
