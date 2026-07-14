import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

const piliNativeGlassTabBarViewType = 'pili/native_glass_tab_bar';
const piliNativeGlassTabBarItems = <({String symbol, String selectedSymbol})>[
  (symbol: 'home', selectedSymbol: 'home.fill'),
  (symbol: 'square.stack', selectedSymbol: 'square.stack.fill'),
  (
    symbol: 'person.crop.circle',
    selectedSymbol: 'person.crop.circle.fill',
  ),
];

bool supportsPiliNativeGlassTabBar({
  TargetPlatform? platform,
}) => !kIsWeb && (platform ?? defaultTargetPlatform) == TargetPlatform.iOS;

Map<String, Object> piliNativeGlassTabBarCreationParams({
  required int selectedIndex,
  required List<String> labels,
}) {
  assert(labels.length == piliNativeGlassTabBarItems.length);
  return <String, Object>{
    'selectedIndex': selectedIndex,
    'items': <Map<String, String>>[
      for (var index = 0; index < piliNativeGlassTabBarItems.length; index++)
        <String, String>{
          'label': labels[index],
          'symbol': piliNativeGlassTabBarItems[index].symbol,
          'selectedSymbol': piliNativeGlassTabBarItems[index].selectedSymbol,
        },
    ],
  };
}

@visibleForTesting
final class PiliNativeGlassTabBarChannel {
  PiliNativeGlassTabBarChannel({
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
      'pili_native_glass_tab_bar_$viewId',
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

class PiliNativeGlassTabBar extends StatefulWidget {
  const PiliNativeGlassTabBar({
    required this.selectedIndex,
    required this.labels,
    required this.onTap,
    super.key,
  }) : assert(labels.length == piliNativeGlassTabBarItems.length);

  final int selectedIndex;
  final List<String> labels;
  final ValueChanged<int> onTap;

  @override
  State<PiliNativeGlassTabBar> createState() => _PiliNativeGlassTabBarState();
}

class _PiliNativeGlassTabBarState extends State<PiliNativeGlassTabBar> {
  late final PiliNativeGlassTabBarChannel _channel =
      PiliNativeGlassTabBarChannel(onTap: (index) => widget.onTap(index));

  @override
  void didUpdateWidget(PiliNativeGlassTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      unawaited(_channel.setSelectedIndex(widget.selectedIndex));
    }
  }

  @override
  void dispose() {
    _channel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50 + MediaQuery.viewPaddingOf(context).bottom,
      child: UiKitView(
        viewType: piliNativeGlassTabBarViewType,
        creationParams: piliNativeGlassTabBarCreationParams(
          selectedIndex: widget.selectedIndex,
          labels: widget.labels,
        ),
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: (viewId) {
          _channel.attach(viewId, widget.selectedIndex);
        },
      ),
    );
  }
}
