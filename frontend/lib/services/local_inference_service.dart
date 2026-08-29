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
    final result = await _channel.invokeMethod<dynamic>('generate', {
      'modelPath': modelPath,
      'prompt': prompt,
      'maxOutputTokens': maxOutputTokens,
      'enableThinking': enableThinking,
    });
    if (result is Map) {
      final text = result['text']?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
      throw StateError('LiteRT-LM returned an empty response.');
    }
    throw StateError('Invalid response from the local model runtime.');
  }
}
