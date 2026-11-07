import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:a2ui_core/a2ui_core.dart' as core;
import 'package:genui/genui.dart';
import 'package:logging/logging.dart';

import 'ai_client.dart';
import 'catalog/trip_catalog.dart';
import 'metrics.dart';

/// One entry in the chat list: user text, model text, or a GenUI surface.
class Message {
  Message.user(String this.text) : isUser = true, surfaceId = null;
  Message.model(String this.text) : isUser = false, surfaceId = null;
  Message.surface(String this.surfaceId) : isUser = false, text = null;

  final bool isUser;
  String? text;
  final String? surfaceId;
}

const String _plannerInstructions = '''
You are a weekend trip planner.
For every request: reply with ONE short sentence, then build ONE surface that shows the plan.
The surface's root is a Column whose children are, in this order:
TripHeader, one DayPlan per day, PlaceCarousel, BudgetBreakdown.
Use only these components plus Text, Card and Row if you really need them.
''';

/// Fix 1, part of the prompt: ask for the UI in small, valid steps so each
/// piece can be shown as soon as it arrives.
const String _streamInSteps = '''
Send the UI in small steps, each its own ```json block:
1. createSurface.
2. updateComponents with the root Column whose children are only the TripHeader, plus the TripHeader itself.
3. For every remaining component, in order: updateComponents re-sending the root Column with its children list extended by the new id, plus the new component.
''';

/// Wires a model, the GenUI SurfaceController and the metrics together for
/// one [DemoMode]. Switching mode creates a new session.
class PlannerSession extends ChangeNotifier {
  PlannerSession({required this.mode, AiClient? client}) {
    final Catalog catalog = switch (mode) {
      DemoMode.naive => naiveCatalog(),
      DemoMode.optimised => optimisedCatalog(),
    };
    controller = SurfaceController(catalogs: [catalog]);
    _agent = PlannerAgent(client: client ?? GeminiClient());

    final prompt = PromptBuilder.chat(
      catalog: catalog,
      systemPromptFragments: [
        _plannerInstructions,
        if (mode == DemoMode.optimised) _streamInSteps,
        PromptFragments.uiGenerationRestriction(
          prefix: PromptBuilder.defaultImportancePrefix,
        ),
      ],
    );
    systemPrompt = prompt.systemPromptJoined();
    _agent.addSystemMessage(systemPrompt);

    _subs.addAll([
      _adapter.incomingMessages.listen(_apply),
      _adapter.incomingText.listen(_appendModelText),
      controller.surfaceUpdates.listen(_onSurfaceUpdate),
      controller.onSubmit.listen(_run),
    ]);
  }

  final DemoMode mode;
  late final SurfaceController controller;
  late final String systemPrompt;
  late final PlannerAgent _agent;
  final A2uiTransportAdapter _adapter = A2uiTransportAdapter();
  final List<StreamSubscription<Object?>> _subs = [];
  final Logger _log = Logger('PlannerSession');

  final List<Message> _messages = [];
  List<Message> get messages => List.unmodifiable(_messages);

  Message? _currentModelText;
  bool _busy = false;
  bool get isBusy => _busy;

  /// Whether the current request has delivered any components yet.
  /// Drives the skeleton in optimised mode.
  bool _componentsArrived = false;
  bool get componentsArrived => _componentsArrived;

  /// Rough size of the system prompt (characters / 4). Good enough to
  /// compare the two modes; check your provider's usage data for exact
  /// numbers.
  int get promptTokens => (systemPrompt.length / 4).round();

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty || _busy) return;
    _messages.add(Message.user(text.trim()));
    notifyListeners();
    await _run(ChatMessage.user(text.trim()));
  }

  Future<void> _run(ChatMessage message) async {
    if (_busy) return;
    _busy = true;
    _componentsArrived = false;
    _currentModelText = null;
    Metrics.instance.startRun(mode, promptTokens);
    notifyListeners();

    final buffered = StringBuffer();
    try {
      await _agent.send(
        message,
        onChunk: (chunk) {
          Metrics.instance.markFirstChunk();
          switch (mode) {
            // Fix 1: hand every chunk to GenUI as soon as it arrives.
            case DemoMode.optimised:
              _adapter.addChunk(chunk);
            // Naive: wait for the whole answer, then hand it over.
            case DemoMode.naive:
              buffered.write(chunk);
          }
        },
      );
      if (mode == DemoMode.naive) _adapter.addChunk(buffered.toString());
    } catch (e, st) {
      _log.severe('Request failed', e, st);
      _messages.add(Message.model('Error: $e'));
    } finally {
      _busy = false;
      Metrics.instance.finishRun();
      notifyListeners();
    }
  }

  /// Applying a message is wrapped in a Timeline event so it shows up in
  /// the DevTools performance view next to the frames.
  void _apply(core.A2uiMessage message) {
    developer.Timeline.timeSync(
      'genui.applyMessage',
      () => controller.handleMessage(message),
    );
  }

  void _appendModelText(String chunk) {
    if (_currentModelText == null) {
      _currentModelText = Message.model('');
      _messages.add(_currentModelText!);
    }
    _currentModelText!.text = (_currentModelText!.text ?? '') + chunk;
    notifyListeners();
  }

  void _onSurfaceUpdate(SurfaceUpdate update) {
    switch (update) {
      case SurfaceAdded(:final surfaceId):
        if (!_messages.any((m) => m.surfaceId == surfaceId)) {
          _messages.add(Message.surface(surfaceId));
          notifyListeners();
        }
      case ComponentsUpdated():
        if (!_componentsArrived) {
          _componentsArrived = true;
          notifyListeners();
        }
      case SurfaceRemoved():
        break;
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    controller.dispose();
    _adapter.dispose();
    _agent.client.dispose();
    super.dispose();
  }
}
