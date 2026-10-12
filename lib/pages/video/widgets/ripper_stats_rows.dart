import 'dart:async';

import 'package:PiliPlus/services/thread_ripper/thread_ripper.dart';
import 'package:flutter/material.dart';

/// Live rows of what the multi-CDN proxy is doing, for the playback info
/// panel.
class RipperStatsRows extends StatefulWidget {
  const RipperStatsRows({
    super.key,
    required this.labelStyle,
    required this.valueStyle,
  });

  final TextStyle labelStyle;
  final TextStyle valueStyle;

  @override
  State<RipperStatsRows> createState() => _RipperStatsRowsState();
}

class _RipperStatsRowsState extends State<RipperStatsRows> {
  late final Timer _timer;
  RipperStats _stats = threadRipper.stats;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() => _stats = threadRipper.stats),
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  static String _rate(double bytesPerSecond) =>
      '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(2)} MB/s';

  /// `upos-sz-mirrorcosov.bilivideo.com` -> `mirrorcosov`
  static String _short(String host) =>
      host.split('.').first.replaceFirst(RegExp(r'^upos-\w+?-'), '');

  @override
  Widget build(BuildContext context) {
    final stats = _stats;
    final rows = <(String, String)>[
      ('CDN Throughput:', _rate(stats.servedRate)),
      ('CDN Overhead:', '${(stats.overhead * 100).toStringAsFixed(1)}%'),
      (
        'CDN Hosts:',
        stats.hosts
            .take(4)
            .map((e) => '${_short(e.$1)} ${_rate(e.$2)}')
            .join('\n'),
      ),
    ];
    return Table(
      defaultVerticalAlignment: TableCellVerticalAlignment.top,
      columnWidths: const {0: IntrinsicColumnWidth(), 1: FlexColumnWidth()},
      children: [
        for (final (label, value) in rows)
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  label,
                  textAlign: TextAlign.end,
                  style: widget.labelStyle,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 14, top: 2, bottom: 2),
                child: Text(
                  value.isEmpty ? '—' : value,
                  style: widget.valueStyle,
                ),
              ),
            ],
          ),
      ],
    );
  }
}
