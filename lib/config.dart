/// Build-time configuration, passed with --dart-define.
///
///   flutter run --profile \
///     --dart-define=GEMINI_API_KEY=your_key \
///     --dart-define=GEMINI_MODEL=gemini-3-flash-preview
library;

const String _geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');

/// The Gemini model to use. Override with --dart-define=GEMINI_MODEL=...
const String geminiModel = String.fromEnvironment(
  'GEMINI_MODEL',
  defaultValue: 'gemini-3-flash-preview',
);

/// The prompt pre-filled in the text field, so the live demo needs no typing.
const String demoPrompt = String.fromEnvironment(
  'DEMO_PROMPT',
  defaultValue:
      'Plan me a 2-day weekend in Kampala for two people, '
      'budget 600,000 UGX. Include places to eat and things to do.',
);

String geminiApiKey() {
  if (_geminiApiKey.isEmpty) {
    throw Exception(
      'No Gemini API key. Run with --dart-define=GEMINI_API_KEY=your_key '
      '(get one at https://aistudio.google.com/app/apikey).',
    );
  }
  return _geminiApiKey;
}
