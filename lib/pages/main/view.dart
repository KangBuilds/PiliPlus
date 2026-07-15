import 'package:PiliPlus/common/widgets/floating_navigation_bar.dart';
import 'package:PiliPlus/common/widgets/flutter/pop_scope.dart';
import 'package:PiliPlus/common/widgets/flutter/tabs.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/pili_native_glass_tab_bar.dart';
import 'package:PiliPlus/common/widgets/route_aware_mixin.dart';
import 'package:PiliPlus/models/common/nav_bar_config.dart';
import 'package:PiliPlus/pages/home/view.dart';
import 'package:PiliPlus/pages/main/controller.dart';
import 'package:PiliPlus/utils/app_scheme.dart';
import 'package:PiliPlus/utils/extension/context_ext.dart';
import 'package:PiliPlus/utils/extension/size_ext.dart';
import 'package:PiliPlus/utils/extension/theme_ext.dart';
import 'package:PiliPlus/utils/mobile_observer.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends PopScopeState<MainApp>
    with RouteAware, RouteAwareMixin, WidgetsBindingObserver {
  final _mainController = Get.put(MainController());
  late EdgeInsets _padding;
  late ThemeData theme;

  @override
  bool get initCanPop => false;

  @override
  void initState() {
    super.initState();
    addObserverMobile(this);
    // FlutterSmartDialog throws
    PiliScheme.init();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _padding = MediaQuery.viewPaddingOf(context);
    theme = Theme.of(context);
    final brightness = theme.brightness;
    NetworkImgLayer.reduce =
        NetworkImgLayer.reduceLuxColor != null && brightness.isDark;
    if (!_mainController.useSideBar) {
      _mainController.useBottomNav = MediaQuery.sizeOf(context).isPortrait;
    }
  }

  @override
  void didPopNext() {
    addObserverMobile(this);
    _mainController
      ..checkUnreadDynamic()
      ..checkDefaultSearch(true)
      ..checkUnread(_mainController.useBottomNav);
    super.didPopNext();
  }

  @override
  void didPushNext() {
    removeObserverMobile(this);
    super.didPushNext();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _mainController
        ..checkUnreadDynamic()
        ..checkDefaultSearch(true)
        ..checkUnread(_mainController.useBottomNav);
    }
  }

  @override
  void dispose() {
    removeObserverMobile(this);
    PiliScheme.listener?.cancel();
    GStorage.close();
    super.dispose();
  }

  @override
  void onPopInvokedWithResult(bool didPop, Object? result) {
    if (!_mainController.directExitOnBack &&
        _mainController.selectedIndex.value != 0) {
      _mainController
        ..setIndex(0)
        ..showBottomBar?.value = true
        ..setSearchBar();
    }
  }

  Widget? get _bottomNav {
    Widget? bottomNav;
    if (_mainController.navigationBars.length > 1) {
      final navigationBars = _mainController.navigationBars;
      if (usesPiliNativeGlassTabBar(
        isPortrait: MediaQuery.orientationOf(context) == Orientation.portrait,
        isTablet: context.isTablet,
        hasRequiredDestinations: _mainController.hasPiliNativeGlassDestinations,
      )) {
        return Obx(
          () => PiliNativeGlassTabBar(
            selectedIndex: _mainController.selectedIndex.value,
            labels: navigationBars.map((item) => item.label).toList(),
            onTap: _mainController.setIndex,
            onSearchTap: _mainController.openSearch,
            searchLabel: '搜索',
          ),
        );
      }
      if (_mainController.floatingNavBar) {
        bottomNav = Obx(
          () => FloatingNavigationBar(
            onDestinationSelected: _mainController.setIndex,
            selectedIndex: _mainController.selectedIndex.value,
            destinations: _mainController.navigationBars
                .map(
                  (e) => FloatingNavigationDestination(
                    label: e.label,
                    icon: _buildIcon(type: e),
                    selectedIcon: _buildIcon(type: e, selected: true),
                  ),
                )
                .toList(),
          ),
        );
      } else if (_mainController.enableMYBar) {
        bottomNav = Obx(
          () => NavigationBar(
            maintainBottomViewPadding: true,
            onDestinationSelected: _mainController.setIndex,
            selectedIndex: _mainController.selectedIndex.value,
            destinations: _mainController.navigationBars
                .map(
                  (e) => NavigationDestination(
                    label: e.label,
                    icon: _buildIcon(type: e),
                    selectedIcon: _buildIcon(type: e, selected: true),
                  ),
                )
                .toList(),
          ),
        );
      } else {
        bottomNav = Obx(
          () => BottomNavigationBar(
            currentIndex: _mainController.selectedIndex.value,
            onTap: _mainController.setIndex,
            iconSize: 16,
            selectedFontSize: 12,
            unselectedFontSize: 12,
            type: .fixed,
            items: _mainController.navigationBars
                .map(
                  (e) => BottomNavigationBarItem(
                    label: e.label,
                    icon: _buildIcon(type: e),
                    activeIcon: _buildIcon(type: e, selected: true),
                  ),
                )
                .toList(),
          ),
        );
      }

      if (_mainController.hideBottomBar) {
        if (_mainController.showBottomBar case final showBottomBar?) {
          return Obx(
            () => AnimatedSlide(
              curve: Curves.easeInOutCubicEmphasized,
              duration: const Duration(milliseconds: 500),
              offset: Offset(0, showBottomBar.value ? 0 : 1),
              child: bottomNav,
            ),
          );
        }
      }
    }

    return bottomNav;
  }

  Widget _sideBar(ThemeData theme) {
    return _mainController.navigationBars.length > 1
        ? context.isTablet && _mainController.optTabletNav
              ? Column(
                  children: [
                    const SizedBox(height: 25),
                    userAndSearchVertical(theme),
                    const Spacer(flex: 2),
                    Expanded(
                      flex: 5,
                      child: SizedBox(
                        width: 130,
                        child: Obx(
                          () => NavigationDrawer(
                            backgroundColor: Colors.transparent,
                            tilePadding: const .symmetric(
                              vertical: 5,
                              horizontal: 12,
                            ),
                            indicatorShape: const RoundedRectangleBorder(
                              borderRadius: .all(.circular(16)),
                            ),
                            onDestinationSelected: _mainController.setIndex,
                            selectedIndex: _mainController.selectedIndex.value,
                            children: _mainController.navigationBars
                                .map(
                                  (e) => NavigationDrawerDestination(
                                    label: Text(e.label),
                                    icon: _buildIcon(type: e),
                                    selectedIcon: _buildIcon(
                                      type: e,
                                      selected: true,
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : Obx(
                  () => NavigationRail(
                    groupAlignment: 0.5,
                    selectedIndex: _mainController.selectedIndex.value,
                    onDestinationSelected: _mainController.setIndex,
                    labelType: .selected,
                    leading: userAndSearchVertical(theme),
                    destinations: _mainController.navigationBars
                        .map(
                          (e) => NavigationRailDestination(
                            label: Text(e.label),
                            icon: _buildIcon(type: e),
                            selectedIcon: _buildIcon(type: e, selected: true),
                          ),
                        )
                        .toList(),
                  ),
                )
        : Container(
            width: 80,
            padding: const .only(top: 10),
            child: userAndSearchVertical(theme),
          );
  }

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (_mainController.mainTabBarView) {
      child = CustomTabBarView(
        scrollDirection: _mainController.useBottomNav ? .horizontal : .vertical,
        physics: const NeverScrollableScrollPhysics(),
        controller: _mainController.controller,
        children: _mainController.navigationBars.map((i) => i.page).toList(),
      );
    } else {
      child = PageView(
        physics: const NeverScrollableScrollPhysics(),
        controller: _mainController.controller,
        children: _mainController.navigationBars.map((i) => i.page).toList(),
      );
    }

    Widget? bottomNav;
    if (_mainController.useBottomNav) {
      bottomNav = _bottomNav;
      child = Row(children: [Expanded(child: child)]);
    } else {
      child = Row(
        children: [
          _sideBar(theme),
          VerticalDivider(
            width: 1,
            endIndent: _padding.bottom,
            color: theme.colorScheme.outline.withValues(alpha: 0.06),
          ),
          Expanded(child: child),
        ],
      );
    }

    child = Scaffold(
      extendBody: true,
      resizeToAvoidBottomInset: false,
      appBar: AppBar(toolbarHeight: 0),
      body: Padding(
        padding: EdgeInsets.only(
          left: _mainController.useBottomNav ? _padding.left : 0.0,
          right: _padding.right,
        ),
        child: child,
      ),
      bottomNavigationBar: bottomNav,
    );

    child = AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: theme.brightness.reverse,
      ),
      child: child,
    );

    return child;
  }

  Widget _buildIcon({required NavigationBarType type, bool selected = false}) {
    final icon = selected ? type.selectIcon : type.icon;
    return type == .dynamics
        ? Obx(
            () {
              final dynCount = _mainController.dynCount.value;
              return Badge(
                isLabelVisible: dynCount > 0,
                label: _mainController.dynamicBadgeMode == .number
                    ? Text(dynCount.toString())
                    : null,
                padding: const .symmetric(horizontal: 6),
                child: icon,
              );
            },
          )
        : icon;
  }

  Widget userAndSearchVertical(ThemeData theme) {
    return Column(
      children: [
        userAvatar(theme: theme, mainController: _mainController),
        const SizedBox(height: 8),
        msgBadge(_mainController),
        IconButton(
          tooltip: '搜索',
          icon: const Icon(
            Icons.search_outlined,
            semanticLabel: '搜索',
          ),
          onPressed: () => Get.toNamed('/search'),
        ),
      ],
    );
  }
}
