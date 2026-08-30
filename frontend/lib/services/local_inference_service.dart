import 'package:flutter/services.dart';

/// Flutter bridge for the native LiteRT-LM runtime.
///
/// The model remains in the app's private models directory; only the prompt
/// and generated text cross this channel. Native inference is run on a
/// background executor so loading a multi-gigabyte model cannot block Flutter.
class LocalInferenceService {
  static const _channel = MethodChannel('teamChaiAndCode/local_model');

  Future<String> generate({
    required String modelPath,
    required String prompt,
    int maxOutputTokens = 512,
    bool enableThinking = false,
  }) async {
    // LiteRT-LM occasionally returns an empty decode (more likely on the first
    // token-heavy tool turn). The engine is already warm, so one retry recovers
    // it far more cheaply than surfacing a hard failure to the user.
    StateError? lastEmpty;
    for (var attempt = 0; attempt < 2; attempt++) {
      final result = await _channel.invokeMethod<dynamic>('generate', {
        'modelPath': modelPath,
        'prompt': prompt,
        'maxOutputTokens': maxOutputTokens,
        'enableThinking': enableThinking,
      });
      if (result is! Map) {
        throw StateError('Invalid response from the local model runtime.');
      }
      final text = result['text']?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
      lastEmpty = StateError('LiteRT-LM returned an empty response.');
    }
    throw lastEmpty!;
  }
}
