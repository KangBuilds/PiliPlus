import 'package:PiliPlus/pages/home/controller.dart';
import 'package:PiliPlus/pages/main/controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

abstract class CommonPageState<T extends StatefulWidget> extends State<T> {
  RxBool? _showTopBar;
  RxBool? _showBottomBar;
  final _mainController = Get.find<MainController>();

  @override
  void initState() {
    super.initState();
    _showBottomBar = _mainController.showBottomBar;
    try {
      _showTopBar = Get.find<HomeController>().showTopBar;
    } catch (_) {}
  }

  Widget onBuild(Widget child) {
    if (_showTopBar != null || _showBottomBar != null) {
      return NotificationListener<UserScrollNotification>(
        onNotification: onUserScrollNotification,
        child: child,
      );
    }
    return child;
  }

  bool onUserScrollNotification(UserScrollNotification notification) {
    if (!_mainController.useBottomNav) return false;
    if (notification.metrics.axis == .horizontal) return false;
    switch (notification.direction) {
      case .forward:
        _showTopBar?.value = true;
        _showBottomBar?.value = true;
      case .reverse:
        _showTopBar?.value = false;
        _showBottomBar?.value = false;
      case _:
    }
    return false;
  }

  @override
  void dispose() {
    _showTopBar = null;
    _showBottomBar = null;
    super.dispose();
  }
}
