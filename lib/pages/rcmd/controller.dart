import 'dart:async';
import 'dart:io';

import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/models/common/account_type.dart';
import 'package:PiliPlus/models/common/rcmd_source.dart';
import 'package:PiliPlus/pages/common/common_list_controller.dart';
import 'package:PiliPlus/pages/rcmd/feed_cache.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/path_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:path/path.dart' as path;

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

  static RcmdFeedCache? _feedCache;

  /// `null` without the app's folder, as in tests: the feed loads as it
  /// would without a cache.
  static RcmdFeedCache? get _cache {
    try {
      return _feedCache ??= RcmdFeedCache(
        File(path.join(appSupportDirPath, 'rcmd_feed.json')),
      );
    } catch (_) {
      return null;
    }
  }

  /// What is shown is last launch's feed, not yet replaced by a fresh one.
  bool _fromCache = false;

  String get _cacheKey {
    final account = Accounts.get(AccountType.recommend);
    return '${rcmdSource.name}:${account.isLogin ? account.mid : 0}';
  }

  List<dynamic> _parse(RcmdSource source, List items) => source == .app
      ? VideoHttp.rcmdItemsApp(items)
      : VideoHttp.rcmdItemsWeb(items);

  @override
  void onInit() {
    super.onInit();
    page = 0;
    _showCached();
    queryData();
  }

  /// Shows last launch's feed while the fresh one is on its way, unless that
  /// one came first.
  Future<void> _showCached() async {
    final source = rcmdSource;
    final key = _cacheKey;
    final items = await _cache?.read(key);
    if (items == null || key != _cacheKey || loadingState.value is! Loading) {
      return;
    }
    try {
      final list = _parse(source, items);
      if (list.isEmpty) return;
      _fromCache = true;
      loadingState.value = Success(list);
    } catch (_) {
      // Kept by an older version, or not readable: the skeleton stays
    }
  }

  @override
  Future<LoadingState> customGetData() async {
    while (true) {
      final version = _sourceVersion;
      final key = _cacheKey;
      final fresh = page == 0;
      void keep(List items) => unawaited(_cache?.add(key, items, fresh: fresh));
      final result = await switch (rcmdSource) {
        RcmdSource.app => VideoHttp.rcmdVideoListApp(
          freshIdx: page,
          onItems: keep,
        ),
        RcmdSource.web => VideoHttp.rcmdVideoList(
          freshIdx: page,
          ps: 20,
          onItems: keep,
        ),
        RcmdSource.desktop => VideoHttp.rcmdVideoList(
          freshIdx: page,
          ps: 30,
          desktop: true,
          onItems: keep,
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
    // Last launch's feed stays when the fresh one cannot be had, offline
    return enableSaveLastData || _fromCache;
  }

  @override
  void handleListResponse(List dataList) {
    if (_fromCache && page == 0) {
      _fromCache = false;
      // Scrolled into last launch's feed: what is under the finger stays
      // put, and the fresh videos come after it
      if (scrollController.hasClients && scrollController.offset > 0) {
        if (loadingState.value case Success(:final response?)) {
          dataList.insertAll(0, response);
        }
        return;
      }
    }
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
