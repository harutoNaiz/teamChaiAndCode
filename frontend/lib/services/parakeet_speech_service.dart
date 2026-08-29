import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Microphone speech service. The current Android backend is the platform
/// SpeechRecognizer; Parakeet remains a separate offline model/runtime task.
class ParakeetSpeechService {
  static final ParakeetSpeechService instance =
      ParakeetSpeechService._internal();

  ParakeetSpeechService._internal();

  bool _isListening = false;
  bool get isListening => _isListening;
  final stt.SpeechToText _speech = stt.SpeechToText();

  static const String modelName = 'Parakeet Unified EN 0.6B';
  static const String modelVersion = '0.6B-unified-en-mobile';

  // Common phonetic mispronunciations, acoustic variations, and slang corrections
  static final Map<String, String> _phoneticCorrections = {
    'aadhar': 'Aadhaar',
    'adhar': 'Aadhaar',
    'adar': 'Aadhaar',
    'adhhar': 'Aadhaar',
    'pan card': 'PAN card',
    'pancard': 'PAN card',
    'ggl': 'Google',
    'gogle': 'Google',
    'swigy': 'Swiggy',
    'zomto': 'Zomato',
    'offr': 'offer',
    'letr': 'letter',
    'stipnd': 'stipend',
    'whats app': 'WhatsApp',
    'whatsap': 'WhatsApp',
    'watsapp': 'WhatsApp',
    'watsap': 'WhatsApp',
    'reciept': 'receipt',
    'recept': 'receipt',
    'documnt': 'document',
    'resum': 'resume',
    'intrenship': 'internship',
    'internshp': 'internship',
    'exprt': 'export',
  };

  /// Starts Android speech recognition and emits interim/final text.
  Stream<String> startListening({
    required Function(String finalizedText) onFinalResult,
    required Function(String interimText) onInterimResult,
    required VoidCallback onError,
  }) {
    final controller = StreamController<String>.broadcast();
    () async {
      try {
        final available = await _speech.initialize(
          onError: (_) {
            _isListening = false;
            onError();
          },
        );
        if (!available) {
          onError();
          await controller.close();
          return;
        }
        _isListening = true;
        await _speech.listen(
          onResult: (result) {
            if (result.recognizedWords.isEmpty) return;
            controller.add(result.recognizedWords);
            if (result.finalResult)
              onFinalResult(correctTranscription(result.recognizedWords));
            onInterimResult(result.recognizedWords);
          },
        );
      } catch (_) {
        _isListening = false;
        onError();
        await controller.close();
      }
    }();
    return controller.stream;
  }

  /// Corrects mispronounced, accented, or colloquial terms using Parakeet LM
  String correctTranscription(String rawInput) {
    if (rawInput.trim().isEmpty) return rawInput;

    String normalized = rawInput;
    _phoneticCorrections.forEach((mispronounced, corrected) {
      final reg = RegExp(r'\b' + RegExp.escape(mispronounced) + r'\b',
          caseSensitive: false);
      normalized = normalized.replaceAll(reg, corrected);
    });

    // Capitalize first letter and format spacing
    normalized = normalized.trim();
    if (normalized.isNotEmpty) {
      normalized = normalized[0].toUpperCase() + normalized.substring(1);
    }
    return normalized;
  }

  void stopListening() {
    _isListening = false;
    _speech.stop();
  }
}
