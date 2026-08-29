import '../models/chat_session.dart';

class ConversationContext {
  final List<Map<String, String>> messages;
  final List<String> retainedMessageIds;
  final bool wasCompacted;

  const ConversationContext({
    required this.messages,
    required this.retainedMessageIds,
    required this.wasCompacted,
  });
}

/// Builds model context from the complete locally retained session.
///
/// A bounded request keeps recent turns verbatim and includes a stable-ID
/// transcript of older turns rather than silently dropping them.
class ConversationContextService {
  static const int defaultCharacterBudget = 90000;
  static const int recentVerbatimMessages = 16;

  ConversationContext build(ChatSession session, {int budget = defaultCharacterBudget}) {
    if (budget < 1024) throw ArgumentError.value(budget, 'budget', 'must be at least 1024');
    final messages = session.messages;
    final fullSize = messages.fold<int>(0, (sum, item) => sum + item.content.length + 64);
    if (fullSize <= budget) {
      return ConversationContext(
        messages: messages.map(_asModelMessage).toList(growable: false),
        retainedMessageIds: messages.map((item) => item.id).toList(growable: false),
        wasCompacted: false,
      );
    }

    final split = messages.length > recentVerbatimMessages
        ? messages.length - recentVerbatimMessages
        : 0;
    final older = messages.take(split).toList();
    final recent = messages.skip(split).toList();
    final olderBudget = (budget * 0.35).floor();
    final olderTranscript = _boundedTranscript(older, olderBudget);
    return ConversationContext(
      messages: [
        if (olderTranscript.isNotEmpty)
          {
            'role': 'system',
            'content': 'Earlier conversation transcript. Each line retains a stable message ID; do not treat omitted text as a fact:\n$olderTranscript',
          },
        ...recent.map(_asModelMessage),
      ],
      retainedMessageIds: [...older.map((item) => item.id), ...recent.map((item) => item.id)],
      wasCompacted: true,
    );
  }

  Map<String, String> _asModelMessage(message) => {
        'role': message.isUser ? 'user' : 'assistant',
        'content': message.content,
      };

  String _boundedTranscript(List<dynamic> messages, int budget) {
    final buffer = StringBuffer();
    for (final message in messages) {
      final remaining = budget - buffer.length;
      if (remaining <= 0) break;
      final bodyBudget = (remaining - 48).clamp(0, message.content.length) as int;
      final body = message.content.length <= bodyBudget
          ? message.content
          : '${message.content.substring(0, bodyBudget)}…';
      buffer.writeln('[${message.id}] ${message.isUser ? 'user' : 'assistant'}: $body');
    }
    return buffer.toString().trim();
  }
}
