import 'dart:async';
import 'dart:developer' as developer;
import 'dart:ui' show FrameTiming;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

enum DemoMode {
  naive('Naive'),
  optimised('Optimised');

  const DemoMode(this.label);
  final String label;
}

/// Numbers for one request, from "send" until the UI has settled.
class RunMetrics {
  RunMetrics({required this.mode, required this.promptTokens});

  final DemoMode mode;

  /// Estimated system-prompt size: characters / 4.
  final int promptTokens;

  /// Send → first chunk from the model.
  int? firstTokenMs;

  /// Send → first frame showing a real trip component.
  int? firstFrameMs;

  /// Send → model stream finished.
  int? totalMs;

  /// build() calls of the tracked trip widgets.
  int builds = 0;

  /// initState() calls of the tracked trip widgets: widgets thrown away
  /// and created again from scratch.
  int mounts = 0;

  /// Frames where build or raster went over the 16.7 ms budget, counted
  /// from the first trip component until the run settles. Frames before
  /// that (a spinner turning while we wait for the model) are not GenUI
  /// work, so they are left out.
  int jankyFrames = 0;
  int frames = 0;

  /// The slowest frame (build or raster, whichever is longer) in that window.
  double worstFrameMs = 0;

  bool settled = false;
}

/// Collects [RunMetrics] for the demo. One shared instance.
///
/// While a run is recording, counters change silently: listeners are only
/// notified when a run starts, when the stream ends and when it settles,
/// so the metrics panel itself doesn't add frames to the measurement.
class Metrics extends ChangeNotifier {
  Metrics._();
  static final Metrics instance = Metrics._();

  static const Duration _frameBudget = Duration(microseconds: 16667);

  /// How long to keep counting frames after the stream ends,
  /// so late layout and image decoding are included.
  static const Duration _settleTime = Duration(milliseconds: 1500);

  final List<RunMetrics> runs = [];
  RunMetrics? _current;
  final Stopwatch _stopwatch = Stopwatch();
  bool _timingsAttached = false;
  bool _firstFrameScheduled = false;
  bool _uiWindowOpen = false;
  Timer? _settleTimer;

  RunMetrics? get current => _current;
  bool get isRecording => _current != null && !_current!.settled;

  void startRun(DemoMode mode, int promptTokens) {
    _attachFrameTimings();
    _settleTimer?.cancel();
    _current = RunMetrics(mode: mode, promptTokens: promptTokens);
    _firstFrameScheduled = false;
    _uiWindowOpen = false;
    _stopwatch
      ..reset()
      ..start();
    developer.Timeline.instantSync('genui.send');
    notifyListeners();
  }

  void markFirstChunk() {
    final RunMetrics? run = _current;
    if (run == null || run.firstTokenMs != null) return;
    run.firstTokenMs = _stopwatch.elapsedMilliseconds;
    developer.Timeline.instantSync('genui.firstToken');
  }

  /// Called from catalog builders. The first call of a run schedules a
  /// post-frame callback: that frame is the first meaningful frame.
  void markComponentBuilt() {
    if (isRecording) _uiWindowOpen = true;
    final RunMetrics? run = _current;
    if (run == null || run.firstFrameMs != null || _firstFrameScheduled) {
      return;
    }
    _firstFrameScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      run.firstFrameMs = _stopwatch.elapsedMilliseconds;
      developer.Timeline.instantSync('genui.firstFrame');
    });
  }

  void countBuild() {
    if (!isRecording) return;
    _current!.builds++;
  }

  void countMount() {
    if (!isRecording) return;
    _current!.mounts++;
  }

  void finishRun() {
    final RunMetrics? run = _current;
    if (run == null) return;
    run.totalMs = _stopwatch.elapsedMilliseconds;
    developer.Timeline.instantSync('genui.streamDone');
    _settleTimer = Timer(_settleTime, () {
      run.settled = true;
      _stopwatch.stop();
      runs.add(run);
      notifyListeners();
    });
    notifyListeners();
  }

  void reset() {
    _settleTimer?.cancel();
    runs.clear();
    _current = null;
    notifyListeners();
  }

  List<RunMetrics> runsFor(DemoMode mode) =>
      runs.where((r) => r.mode == mode).toList();

  /// Average of [pick] over the settled runs of [mode], ignoring nulls.
  double? average(DemoMode mode, num? Function(RunMetrics) pick) {
    final values = runsFor(mode).map(pick).whereType<num>().toList();
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a + b) / values.length;
  }

  /// A Markdown table of the averages, ready to paste into notes.
  String toMarkdown() {
    String fmt(double? v) => v == null ? '–' : v.round().toString();
    final b = StringBuffer()
      ..writeln('| Metric | Naive | Optimised |')
      ..writeln('| --- | --- | --- |');
    final rows = <String, num? Function(RunMetrics)>{
      'Runs': (r) => 1,
      'Prompt tokens (est.)': (r) => r.promptTokens,
      'First token (ms)': (r) => r.firstTokenMs,
      'Prompt → first frame (ms)': (r) => r.firstFrameMs,
      'Stream done (ms)': (r) => r.totalMs,
      'Widget builds': (r) => r.builds,
      'Widget remounts': (r) => r.mounts,
      'Janky frames': (r) => r.jankyFrames,
      'Worst frame (ms)': (r) => r.worstFrameMs,
    };
    rows.forEach((label, pick) {
      if (label == 'Runs') {
        b.writeln(
          '| Runs | ${runsFor(DemoMode.naive).length} '
          '| ${runsFor(DemoMode.optimised).length} |',
        );
      } else {
        b.writeln(
          '| $label | ${fmt(average(DemoMode.naive, pick))} '
          '| ${fmt(average(DemoMode.optimised, pick))} |',
        );
      }
    });
    return b.toString();
  }

  void _attachFrameTimings() {
    if (_timingsAttached) return;
    _timingsAttached = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void _onTimings(List<FrameTiming> timings) {
    if (!isRecording || !_uiWindowOpen) return;
    final RunMetrics run = _current!;
    for (final t in timings) {
      run.frames++;
      final Duration slowest = t.buildDuration > t.rasterDuration
          ? t.buildDuration
          : t.rasterDuration;
      final double ms = slowest.inMicroseconds / 1000;
      if (ms > run.worstFrameMs) run.worstFrameMs = ms;
      if (slowest > _frameBudget) run.jankyFrames++;
    }
  }
}
