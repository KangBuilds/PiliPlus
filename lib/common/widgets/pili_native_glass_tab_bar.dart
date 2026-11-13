import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';

const piliNativeGlassTabBarItems = <({String symbol, String selectedSymbol})>[
  (symbol: 'house', selectedSymbol: 'house.fill'),
  (symbol: 'square.stack', selectedSymbol: 'square.stack.fill'),
  (
    symbol: 'person.crop.circle',
    selectedSymbol: 'person.crop.circle.fill',
  ),
];

class PiliNativeGlassTabBar extends StatefulWidget {
  const PiliNativeGlassTabBar({
    required this.selectedIndex,
    required this.labels,
    required this.onTap,
    required this.onSearchTap,
    required this.searchLabel,
    super.key,
  }) : assert(labels.length == piliNativeGlassTabBarItems.length);

  final int selectedIndex;
  final List<String> labels;
  final ValueChanged<int> onTap;
  final VoidCallback onSearchTap;
  final String searchLabel;

  @override
  State<PiliNativeGlassTabBar> createState() => _PiliNativeGlassTabBarState();
}

class _PiliNativeGlassTabBarState extends State<PiliNativeGlassTabBar> {
  void _onTap(int index) {
    if (index == widget.labels.length) {
      // Rebuild so the dependency restores the content tab after selecting search.
      setState(() {});
      widget.onSearchTap();
    } else {
      widget.onTap(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        platformBrightness: Theme.of(context).brightness,
      ),
      child: IOS26NativeTabBar(
        selectedIndex: widget.selectedIndex,
        height: 50 + MediaQuery.viewPaddingOf(context).bottom,
        destinations: [
          for (
            var index = 0;
            index < piliNativeGlassTabBarItems.length;
            index++
          )
            AdaptiveNavigationDestination(
              icon: piliNativeGlassTabBarItems[index].symbol,
              selectedIcon: piliNativeGlassTabBarItems[index].selectedSymbol,
              label: widget.labels[index],
            ),
          AdaptiveNavigationDestination(
            icon: 'magnifyingglass',
            label: widget.searchLabel,
            isSearch: true,
          ),
        ],
        onTap: _onTap,
      ),
    );
  }
}
