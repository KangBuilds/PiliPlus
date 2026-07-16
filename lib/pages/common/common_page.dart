import 'package:PiliPlus/pages/home/controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

abstract class CommonPageState<T extends StatefulWidget> extends State<T> {
  RxBool? _showTopBar;

  @override
  void initState() {
    super.initState();
    try {
      _showTopBar = Get.find<HomeController>().showTopBar;
    } catch (_) {}
  }

  Widget onBuild(Widget child) {
    if (_showTopBar != null) {
      return NotificationListener<UserScrollNotification>(
        onNotification: onUserScrollNotification,
        child: child,
      );
    }
    return child;
  }

  bool onUserScrollNotification(UserScrollNotification notification) {
    if (notification.metrics.axis == .horizontal) return false;
    switch (notification.direction) {
      case .forward:
        _showTopBar?.value = true;
      case .reverse:
        _showTopBar?.value = false;
      case _:
    }
    return false;
  }

  @override
  void dispose() {
    _showTopBar = null;
    super.dispose();
  }
}
