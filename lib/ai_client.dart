import 'package:dartantic_ai/dartantic_ai.dart' as dartantic;
import 'package:genui/genui.dart';

import 'config.dart';

/// Streams text from a model. Kept behind an interface so the
/// rest of the app doesn't care which provider is used.
abstract interface class AiClient {
  Stream<String> sendStream(
    String prompt, {
    required List<dartantic.ChatMessage> history,
  });

  void dispose();
}

/// Gemini through package:dartantic_ai, the same setup the official
/// GenUI examples use.
class GeminiClient implements AiClient {
  GeminiClient() {
    _agent = dartantic.Agent.forProvider(
      dartantic.GoogleProvider(apiKey: geminiApiKey()),
      chatModelName: geminiModel,
    );
  }

  late final dartantic.Agent _agent;

  @override
  Stream<String> sendStream(
    String prompt, {
    required List<dartantic.ChatMessage> history,
  }) async* {
    await for (final result in _agent.sendStream(prompt, history: history)) {
      if (result.output.isNotEmpty) yield result.output;
    }
  }

  @override
  void dispose() {}
}

/// Keeps the conversation history and turns GenUI [ChatMessage]s
/// (typed text or UI interactions) into model requests.
class PlannerAgent {
  PlannerAgent({required this.client});

  final AiClient client;
  final List<dartantic.ChatMessage> _history = [];

  void addSystemMessage(String content) {
    _history.add(dartantic.ChatMessage.system(content));
  }

  /// Sends [message] and calls [onChunk] for every streamed text chunk.
  Future<void> send(
    ChatMessage message, {
    required void Function(String chunk) onChunk,
  }) async {
    final buffer = StringBuffer();
    for (final part in message.parts) {
      if (part.isUiInteractionPart) {
        buffer.write(part.asUiInteractionPart!.interaction);
      } else if (part is TextPart) {
        buffer.write(part.text);
      }
    }
    final String text = buffer.toString();
    if (text.isEmpty) return;

    final history = List<dartantic.ChatMessage>.of(_history);
    final response = StringBuffer();
    await for (final chunk in client.sendStream(text, history: history)) {
      response.write(chunk);
      onChunk(chunk);
    }

    _history
      ..add(dartantic.ChatMessage.user(text))
      ..add(dartantic.ChatMessage.model(response.toString()));
  }
}
