import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:logging/logging.dart';

import 'catalog/trip_widgets.dart';
import 'config.dart';
import 'metrics.dart';
import 'metrics_panel.dart';
import 'planner_session.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Keep logging quiet: verbose logging on every message would skew the
  // numbers we're trying to measure.
  Logger.root.level = Level.WARNING;
  Logger.root.onRecord.listen(
    (r) => debugPrint('${r.level.name} ${r.loggerName}: ${r.message}'),
  );
  runApp(const DemoApp());
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GenUI Performance Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4285F4)),
      ),
      home: const PlannerScreen(),
    );
  }
}

class PlannerScreen extends StatefulWidget {
  const PlannerScreen({super.key});

  @override
  State<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends State<PlannerScreen> {
  final _input = TextEditingController(text: demoPrompt);
  final _scroll = ScrollController();
  DemoMode _mode = DemoMode.naive;
  late PlannerSession _session;
  bool _showMetrics = false;
  bool _perfOverlay = false;

  @override
  void initState() {
    super.initState();
    _session = _createSession();
  }

  PlannerSession _createSession() =>
      PlannerSession(mode: _mode)..addListener(_scrollToEnd);

  void _switchMode(DemoMode mode) {
    if (mode != _mode) _restart(mode);
  }

  /// Fresh conversation in the same mode, so every measured run starts
  /// from the same state.
  void _newConversation() => _restart(_mode);

  void _restart(DemoMode mode) {
    if (_session.isBusy) return;
    setState(() {
      _session
        ..removeListener(_scrollToEnd)
        ..dispose();
      _mode = mode;
      _session = _createSession();
      _input.text = demoPrompt;
    });
  }

  Future<void> _send() async {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    await _session.sendMessage(text);
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Weekend Planner'),
        actions: [
          IconButton(
            tooltip: 'Performance overlay',
            isSelected: _perfOverlay,
            icon: const Icon(Icons.speed_outlined),
            selectedIcon: const Icon(Icons.speed),
            onPressed: () => setState(() => _perfOverlay = !_perfOverlay),
          ),
          IconButton(
            tooltip: 'Metrics',
            isSelected: _showMetrics,
            icon: const Icon(Icons.insights_outlined),
            selectedIcon: const Icon(Icons.insights),
            onPressed: () => setState(() => _showMetrics = !_showMetrics),
          ),
          IconButton(
            tooltip: 'New conversation',
            icon: const Icon(Icons.refresh),
            onPressed: _newConversation,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SegmentedButton<DemoMode>(
              segments: [
                for (final m in DemoMode.values)
                  ButtonSegment(value: m, label: Text(m.label)),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => _switchMode(s.first),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          ListenableBuilder(
            listenable: _session,
            builder: (context, _) => Column(
              children: [
                if (_showMetrics) const MetricsPanel(),
                Expanded(child: _messageList()),
                _inputBar(),
              ],
            ),
          ),
          // Pinned just above the input bar so it never covers the
          // metrics panel or the top of the plan.
          if (_perfOverlay)
            Positioned(
              left: 0,
              right: 0,
              bottom: 88,
              child: IgnorePointer(child: PerformanceOverlay.allEnabled()),
            ),
        ],
      ),
    );
  }

  Widget _messageList() {
    final messages = _session.messages;
    final showSkeleton =
        _session.isBusy &&
        _mode == DemoMode.optimised &&
        !_session.componentsArrived;
    final showSpinner = _session.isBusy && _mode == DemoMode.naive;
    final extra = (showSkeleton || showSpinner) ? 1 : 0;

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: messages.length + extra,
      itemBuilder: (context, i) {
        if (i == messages.length) {
          return showSkeleton
              ? const TripSkeleton()
              : const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
        }
        final m = messages[i];
        if (m.surfaceId != null) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: RepaintBoundary(
              child: Surface(
                key: ValueKey(m.surfaceId),
                surfaceContext: _session.controller.contextFor(m.surfaceId!),
              ),
            ),
          );
        }
        return _bubble(m);
      },
    );
  }

  Widget _bubble(Message m) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: m.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: m.isUser
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(m.text ?? ''),
      ),
    );
  }

  Widget _inputBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 3,
                enabled: !_session.isBusy,
                decoration: const InputDecoration(
                  hintText: 'Where are you going this weekend?',
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            IconButton.filled(
              icon: const Icon(Icons.send),
              onPressed: _session.isBusy ? null : _send,
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _session.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }
}
