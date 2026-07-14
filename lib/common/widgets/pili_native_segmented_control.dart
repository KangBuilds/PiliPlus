// The platform-view architecture is adapted from adaptive_platform_ui:
// https://github.com/berkaycatak/adaptive_platform_ui
// Copyright (c) 2025 Berkay Catak. Licensed under the MIT License.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const piliNativeSegmentedControlViewType = 'pili/native_segmented_control';

Map<String, Object> piliNativeSegmentedControlCreationParams({
  required List<String> labels,
  required int selectedIndex,
}) => <String, Object>{
  'labels': labels,
  'selectedIndex': selectedIndex,
};

@visibleForTesting
final class PiliNativeSegmentedControlChannel {
  PiliNativeSegmentedControlChannel({
    required this.onTap,
    this.binaryMessenger,
  });

  final ValueChanged<int> onTap;
  final BinaryMessenger? binaryMessenger;
  MethodChannel? _channel;
  int? _lastSelectedIndex;

  void attach(int viewId, int selectedIndex) {
    _channel?.setMethodCallHandler(null);
    final channel = MethodChannel(
      'pili_native_segmented_control_$viewId',
      const StandardMethodCodec(),
      binaryMessenger,
    );
    _channel = channel;
    _lastSelectedIndex = selectedIndex;
    channel.setMethodCallHandler(handleMethodCall);
  }

  Future<dynamic> handleMethodCall(MethodCall call) async {
    if (call.method == 'valueChanged') {
      final arguments = call.arguments as Map<Object?, Object?>?;
      final index = (arguments?['index'] as num?)?.toInt();
      if (index != null) {
        _lastSelectedIndex = index;
        onTap(index);
      }
    }
    return null;
  }

  Future<void> setSelectedIndex(int index) async {
    final channel = _channel;
    if (channel == null || _lastSelectedIndex == index) return;
    _lastSelectedIndex = index;
    await channel.invokeMethod<void>('setSelectedIndex', <String, int>{
      'index': index,
    });
  }

  void dispose() {
    _channel?.setMethodCallHandler(null);
    _channel = null;
    _lastSelectedIndex = null;
  }
}

class PiliNativeSegmentedControl extends StatefulWidget {
  const PiliNativeSegmentedControl({
    required this.controller,
    required this.labels,
    required this.onTap,
    super.key,
  }) : assert(labels.length == controller.length);

  final TabController controller;
  final List<String> labels;
  final ValueChanged<int> onTap;

  @override
  State<PiliNativeSegmentedControl> createState() =>
      _PiliNativeSegmentedControlState();
}

class _PiliNativeSegmentedControlState
    extends State<PiliNativeSegmentedControl> {
  late final PiliNativeSegmentedControlChannel _channel =
      PiliNativeSegmentedControlChannel(onTap: (index) => widget.onTap(index));
  late int _controllerIndex;

  @override
  void initState() {
    super.initState();
    _controllerIndex = widget.controller.index;
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(PiliNativeSegmentedControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
    }
    _handleControllerChanged();
  }

  void _handleControllerChanged() {
    final index = widget.controller.index;
    if (_controllerIndex == index) return;
    _controllerIndex = index;
    unawaited(_channel.setSelectedIndex(index));
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    _channel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: UiKitView(
        viewType: piliNativeSegmentedControlViewType,
        creationParams: piliNativeSegmentedControlCreationParams(
          labels: widget.labels,
          selectedIndex: widget.controller.index,
        ),
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: (viewId) {
          _controllerIndex = widget.controller.index;
          _channel.attach(viewId, _controllerIndex);
        },
      ),
    );
  }
}
