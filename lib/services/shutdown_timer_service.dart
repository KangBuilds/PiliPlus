// 定时关闭服务
import 'dart:async';

import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_status.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:collection/collection.dart';
import 'package:flutter/cupertino.dart' show CupertinoPicker;
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

final shutdownTimerService = ShutdownTimerService._internal();

const _kPickerSqueeze = 1.25;
const _kPickerItemExtent = 38.0;

class ShutdownTimerService {
  ShutdownTimerService._internal();

  VoidCallback? onPause;
  ValueGetter<bool>? isPlaying;

  Timer? _shutdownTimer;
  DateTime? _deadline;
  DateTime? get deadline => _deadline;
  bool get isActive => _shutdownTimer?.isActive ?? false;
  int _durationInMinutes = 0;
  bool _isWaiting = false;
  bool get isWaiting => _isWaiting;
  bool _waitUntilCompleted = false;

  void _stopTimer() {
    _deadline = null;
    if (_shutdownTimer != null) {
      _shutdownTimer!.cancel();
      _shutdownTimer = null;
    }
  }

  void reset([int durationInMinutes = 0]) {
    _stopTimer();
    _isWaiting = false;
    _durationInMinutes = durationInMinutes;
  }

  void _startShutdownTimer(int durationInMinutes) {
    reset(durationInMinutes);
    if (durationInMinutes == 0) {
      SmartDialog.showToast('取消定时关闭');
      return;
    }
    SmartDialog.showToast('设置 ${_format(durationInMinutes)} 后定时关闭');
    _deadline = DateTime.now().add(Duration(minutes: durationInMinutes));
    _shutdownTimer = Timer(
      Duration(minutes: durationInMinutes),
      _handleShutdown,
    );
  }

  void _handleShutdown() {
    late final player = PlPlayerController.instance;
    final isPlaying =
        this.isPlaying?.call() ?? player?.playerStatus.isPlaying ?? false;
    if (isPlaying) {
      if (_waitUntilCompleted) {
        _isWaiting = true;
      } else {
        _durationInMinutes = 0;
        (onPause ?? player?.pause)?.call();
        SmartDialog.showToast('定时时间已到，已暂停');
      }
    }
  }

  void handleWaiting() {
    _isWaiting = false;
    _durationInMinutes = 0;
    SmartDialog.showToast('定时时间已到，已暂停');
  }

  static (int hour, int minute) _parseMinutes(int minutes) =>
      (minutes ~/ 60, minutes % 60);

  static String _format(int minutes) {
    if (minutes == 60) return '60分钟';
    final (int hour, int minute) = _parseMinutes(minutes);
    if (hour > 0 && minute > 0) {
      return '$hour小时$minute分钟';
    } else if (hour > 0) {
      return '$hour小时';
    } else {
      return '$minute分钟';
    }
  }

  Widget _pickerBuilder(
    int count, {
    required ValueChanged<int> onSelectedItemChanged,
    required FixedExtentScrollController scrollController,
  }) {
    return CupertinoPicker(
      squeeze: _kPickerSqueeze,
      itemExtent: _kPickerItemExtent,
      scrollController: scrollController,
      onSelectedItemChanged: onSelectedItemChanged,
      children: List.generate(
        count,
        (index) => Center(
          child: Text(
            index.toString().padLeft(2, '0'),
            style: const TextStyle(fontSize: 20, letterSpacing: .4),
          ),
        ),
      ),
    );
  }

  void _showTimePickerDialog(
    BuildContext context,
    VoidCallback onCountdown,
    StateSetter setState,
  ) {
    final (initialHour, initialMinute) = _parseMinutes(_durationInMinutes);
    var hour = initialHour;
    var minute = initialMinute;
    final hourController = FixedExtentScrollController(initialItem: hour);
    final minuteController = FixedExtentScrollController(initialItem: minute);

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        contentPadding: const .fromLTRB(20, 6, 20, 0),
        actionsPadding: const .fromLTRB(20, 0, 20, 16),
        constraints: const .tightFor(width: 320, height: 320),
        content: Row(
          children: [
            Expanded(
              child: _pickerBuilder(
                25,
                scrollController: hourController,
                onSelectedItemChanged: (value) => hour = value,
              ),
            ),
            const Text('时'),
            const SizedBox(width: 10),
            Expanded(
              child: _pickerBuilder(
                60,
                scrollController: minuteController,
                onSelectedItemChanged: (value) => minute = value,
              ),
            ),
            const Text('分'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              '取消',
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _startShutdownTimer(hour * 60 + minute);
              onCountdown();
              setState(() {});
            },
            child: const Text('确认'),
          ),
        ],
      ),
    ).whenComplete(() {
      hourController.dispose();
      minuteController.dispose();
    });
  }

  void showScheduleExitDialog(
    BuildContext context, {
    required bool isFullScreen,
  }) {
    const Set<int> scheduleTimeMinutes = {0, 15, 30, 45, 60};
    const TextStyle titleStyle = TextStyle(fontSize: 14);
    PageUtils.showVideoBottomSheet(
      context,
      maxWidth: 512,
      child: ShutdownPanel(
        builder: (_, countdown, onCountdown, setState) {
          final ThemeData theme = Theme.of(context);
          return Theme(
            data: theme,
            child: Padding(
              padding: const .all(12),
              child: Material(
                clipBehavior: .hardEdge,
                color: theme.colorScheme.surface,
                borderRadius: const .all(.circular(12)),
                child: ListView(
                  padding: const .symmetric(vertical: 14),
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        const Text('定时关闭', style: titleStyle),
                        countdown,
                      ],
                    ),
                    const SizedBox(height: 10),
                    ...{...scheduleTimeMinutes, _durationInMinutes}
                        .sorted(Comparable.compare)
                        .map(
                          (minutes) => ListTile(
                            dense: true,
                            onTap: () {
                              Navigator.pop(context);
                              _startShutdownTimer(minutes);
                            },
                            title: Text(
                              switch (minutes) {
                                0 => '禁用',
                                _ => _format(minutes),
                              },
                              style: titleStyle,
                            ),
                            trailing: _durationInMinutes == minutes
                                ? Icon(
                                    size: 20,
                                    Icons.done,
                                    color: theme.colorScheme.primary,
                                  )
                                : null,
                          ),
                        ),
                    ListTile(
                      dense: true,
                      onTap: () =>
                          _showTimePickerDialog(context, onCountdown, setState),
                      title: const Text('自定义', style: titleStyle),
                    ),
                    Builder(
                      builder: (context) {
                        void onChanged([_]) {
                          _waitUntilCompleted = !_waitUntilCompleted;
                          (context as Element).markNeedsBuild();
                        }

                        return ListTile(
                          dense: true,
                          onTap: onChanged,
                          title: const Text('额外等待视频播放完毕', style: titleStyle),
                          trailing: Transform.scale(
                            alignment: Alignment.centerRight,
                            scale: 0.8,
                            child: Switch(
                              value: _waitUntilCompleted,
                              onChanged: onChanged,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

typedef ShutdownStatefulWidgetBuilder =
    Widget Function(
      BuildContext context,
      Widget countdown,
      VoidCallback onCountdown,
      StateSetter setState,
    );

class ShutdownPanel extends StatefulWidget {
  const ShutdownPanel({
    super.key,
    required this.builder,
    this.buildCountdownText = _kBuildCountdownText,
  });

  final ShutdownStatefulWidgetBuilder builder;
  final Widget Function(String? text) buildCountdownText;

  static Widget _kBuildCountdownText(String? text) {
    if (text == null) {
      return const SizedBox.shrink();
    }
    return Text(text);
  }

  @override
  State<ShutdownPanel> createState() => _ShutdownPanelState();
}

class _ShutdownPanelState extends State<ShutdownPanel> with ShutdownMixin {
  @override
  Widget build(BuildContext context) {
    final countdown = Obx(() => widget.buildCountdownText(countdownText.value));
    return widget.builder(context, countdown, _startTimer, setState);
  }
}

mixin ShutdownMixin<T extends StatefulWidget> on State<T> {
  Timer? _countdownTimer;
  final RxnString countdownText = RxnString(null);

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _updateCountdownTextEnd([String? value]) {
    _stopTimer();
    countdownText.value = value;
  }

  bool _updateCountdownText([_]) {
    if (shutdownTimerService.isWaiting) {
      _updateCountdownTextEnd('当前播放结束后关闭');
      return false;
    }
    final deadline = shutdownTimerService.deadline;
    if (deadline == null) {
      _updateCountdownTextEnd();
      return false;
    }
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= .zero) {
      _updateCountdownTextEnd();
      return false;
    }
    countdownText.value = DurationUtils.formatDuration(remaining.inSeconds);
    return true;
  }

  void _startTimer() {
    _stopTimer();
    if (_updateCountdownText()) {
      _countdownTimer = .periodic(
        const Duration(seconds: 1),
        _updateCountdownText,
      );
    }
  }

  void _stopTimer() {
    if (_countdownTimer != null) {
      _countdownTimer!.cancel();
      _countdownTimer = null;
    }
  }

  @override
  void dispose() {
    _stopTimer();
    super.dispose();
  }
}
