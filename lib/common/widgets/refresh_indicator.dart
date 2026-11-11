import 'package:flutter/material.dart';

class RefreshStatusIndicator extends StatelessWidget {
  const RefreshStatusIndicator({super.key, required this.isRefreshing});

  final bool isRefreshing;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 200),
    transitionBuilder: (child, animation) =>
        ScaleTransition(scale: animation, child: child),
    child: isRefreshing
        ? Center(
            child: SizedBox.fromSize(
              size: const Size.square(40),
              child: Material(
                type: MaterialType.circle,
                color: Theme.of(context).colorScheme.onSecondary,
                elevation: 2,
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            ),
          )
        : const SizedBox.shrink(),
  );
}
