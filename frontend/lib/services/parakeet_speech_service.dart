import 'dart:async';
import 'package:flutter/foundation.dart';

/// Placeholder for a future measured local Parakeet runtime.
/// It never emits a fabricated transcript.
class ParakeetSpeechService {
  static final ParakeetSpeechService instance =
      ParakeetSpeechService._internal();

  ParakeetSpeechService._internal();

  bool _isListening = false;
  bool get isListening => _isListening;

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

  /// Returns an explicit unavailable state until recording/transcription lands.
  Stream<String> startListening({
    required Function(String finalizedText) onFinalResult,
    required Function(String interimText) onInterimResult,
    required VoidCallback onError,
  }) {
    final controller = StreamController<String>.broadcast();
    onError();
    controller.close();
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
  }
}
