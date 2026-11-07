import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'metrics.dart';

/// Shows the last run and the averages per mode. Hidden by default during
/// the live demo; tap the chart icon in the app bar to open it.
class MetricsPanel extends StatelessWidget {
  const MetricsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: Metrics.instance,
      builder: (context, _) {
        final m = Metrics.instance;
        String fmt(double? v, [String unit = '']) =>
            v == null ? '–' : '${v.round()}$unit';

        TableRow row(String label, num? Function(RunMetrics) pick,
            [String unit = '']) {
          return TableRow(
            children: [
              _cell(label),
              _cell(fmt(m.average(DemoMode.naive, pick), unit), end: true),
              _cell(fmt(m.average(DemoMode.optimised, pick), unit), end: true),
            ],
          );
        }

        return Material(
          color: theme.colorScheme.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        m.isRecording
                            ? 'Recording ${m.current!.mode.label} run…'
                            : 'Averages over settled runs',
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copy as Markdown',
                      icon: const Icon(Icons.copy_all_outlined),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: m.toMarkdown()));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Copied results')),
                        );
                      },
                    ),
                    IconButton(
                      tooltip: 'Reset',
                      icon: const Icon(Icons.restart_alt),
                      onPressed: m.reset,
                    ),
                  ],
                ),
                Table(
                  columnWidths: const {
                    0: FlexColumnWidth(2.2),
                    1: FlexColumnWidth(),
                    2: FlexColumnWidth(),
                  },
                  children: [
                    TableRow(
                      children: [
                        _cell('', bold: true),
                        _cell(
                          'Naive (${m.runsFor(DemoMode.naive).length})',
                          bold: true,
                          end: true,
                        ),
                        _cell(
                          'Optimised (${m.runsFor(DemoMode.optimised).length})',
                          bold: true,
                          end: true,
                        ),
                      ],
                    ),
                    row('Prompt tokens (est.)', (r) => r.promptTokens),
                    row('First token', (r) => r.firstTokenMs, ' ms'),
                    row('Prompt → first frame', (r) => r.firstFrameMs, ' ms'),
                    row('Stream done', (r) => r.totalMs, ' ms'),
                    row('Widget builds', (r) => r.builds),
                    row('Widget remounts', (r) => r.mounts),
                    row('Janky frames', (r) => r.jankyFrames),
                    row('Worst frame', (r) => r.worstFrameMs, ' ms'),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Widget _cell(String text, {bool bold = false, bool end = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Text(
          text,
          textAlign: end ? TextAlign.end : TextAlign.start,
          style: TextStyle(
            fontSize: 13,
            fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      );
}
