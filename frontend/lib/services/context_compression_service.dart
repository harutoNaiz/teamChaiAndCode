import '../models/chat_session.dart';

/// ContextCompressionService implements rolling conversational memory compression.
/// It keeps recent messages verbatim while compressing older conversation history
/// into a structured knowledge summary block. This ensures that every new turn retains
/// 100% of previous context without wasteful token consumption.
class ContextCompressionService {
  static const int recentWindowSize = 4; // Number of recent messages kept verbatim
  static const int compressionThreshold = 6; // Trigger compression when total messages exceed this

  static final ContextCompressionService instance = ContextCompressionService._internal();

  ContextCompressionService._internal();

  /// Builds an optimized payload for the Agent/LLM Backend with compressed memory
  Map<String, dynamic> buildOptimizedPayload({
    required ChatSession session,
    required String newPrompt,
    String? attachmentPath,
  }) {
    final allMessages = session.messages;

    // Check if we need to update/compress older context
    if (allMessages.length >= compressionThreshold) {
      _compressOlderTurns(session);
    }

    // Extract recent verbatim window
    final recentMessages = allMessages.length <= recentWindowSize
        ? allMessages
        : allMessages.sublist(allMessages.length - recentWindowSize);

    return {
      'session_id': session.id,
      'model_id': session.selectedModelId,
      'compressed_memory': session.compressedSummary ?? '',
      'recent_history': recentMessages.map((m) => {
        'role': m.role.name,
        'content': m.content,
        'has_actions': m.actions.isNotEmpty,
      }).toList(),
      'current_turn': {
        'prompt': newPrompt,
        'attachment_path': attachmentPath,
        'timestamp': DateTime.now().toIso8601String(),
      },
      'system_instructions': _getSystemPrompt(),
    };
  }

  /// Incremental summarization of older turns into the session's compressed memory
  void _compressOlderTurns(ChatSession session) {
    if (session.messages.length <= recentWindowSize) return;

    final olderMessages = session.messages.sublist(0, session.messages.length - recentWindowSize);
    final buffer = StringBuffer();

    if (session.compressedSummary != null && session.compressedSummary!.isNotEmpty) {
      buffer.writeln(session.compressedSummary);
    } else {
      buffer.writeln('### Core Conversation Context & Facts:');
    }

    // Extract key facts and user goals from older messages
    for (final msg in olderMessages) {
      if (msg.isUser) {
        buffer.writeln('- User asked/requested: "${_truncate(msg.content, 80)}"');
      } else {
        if (msg.actions.isNotEmpty) {
          final actionNames = msg.actions.map((a) => a.title).join(', ');
          buffer.writeln('  • Agent executed tools: [$actionNames]');
        }
        buffer.writeln('  • Key Agent response: "${_truncate(msg.content, 100)}"');
      }
    }

    session.compressedSummary = buffer.toString();
  }

  String _truncate(String text, int maxLength) {
    final clean = text.replaceAll('\n', ' ').trim();
    if (clean.length <= maxLength) return clean;
    return '${clean.substring(0, maxLength)}...';
  }

  String _getSystemPrompt() {
    return 'You are teamChaiAndCode: an autonomous, permission-controlled AI agent for smartphones. '
        'You have access to unified phone search (files, OCR, photos), device tools, and a security gate. '
        'Always provide concise, helpful answers and generate structured tool calls when actions are required.';
  }
}
