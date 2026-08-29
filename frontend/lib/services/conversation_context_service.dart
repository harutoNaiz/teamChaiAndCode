import '../models/chat_session.dart';
import '../models/chat_message.dart';

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

  ConversationContext build(ChatSession session,
      {int budget = defaultCharacterBudget}) {
    if (budget < 1024)
      throw ArgumentError.value(budget, 'budget', 'must be at least 1024');
    final List<ChatMessage> messages = session.messages;
    final fullSize =
        messages.fold<int>(0, (sum, item) => sum + item.content.length + 64);
    if (fullSize <= budget) {
      return ConversationContext(
        messages: messages.map(_asModelMessage).toList(growable: false),
        retainedMessageIds:
            messages.map((item) => item.id).toList(growable: false),
        wasCompacted: false,
      );
    }

    final split = messages.length > recentVerbatimMessages
        ? messages.length - recentVerbatimMessages
        : 0;
    final older = messages.take(split).toList();
    var recent = messages.skip(split).toList();
    final recentBudget = (budget * 0.65).floor();
    if (_sizeOf(recent) > recentBudget) {
      recent = _truncateMessages(recent, recentBudget);
    }
    final olderBudget = budget - _sizeOf(recent);
    final olderTranscript = _boundedTranscript(older, olderBudget);
    return ConversationContext(
      messages: [
        if (olderTranscript.isNotEmpty)
          {
            'role': 'system',
            'content':
                'Earlier conversation transcript. Each line retains a stable message ID; do not treat omitted text as a fact:\n$olderTranscript',
          },
        ...recent.map(_asModelMessage),
      ],
      retainedMessageIds: [
        ...older.map((item) => item.id),
        ...recent.map((item) => item.id)
      ],
      wasCompacted: true,
    );
  }

  int _sizeOf(List<ChatMessage> messages) =>
      messages.fold<int>(0, (sum, item) => sum + item.content.length + 64);

  List<ChatMessage> _truncateMessages(List<ChatMessage> messages, int budget) {
    final bodyBudget = ((budget ~/ messages.length) - 64).clamp(1, 8192);
    return messages
        .map((message) => ChatMessage(
              id: message.id,
              role: message.role,
              content: _truncatePreservingEnds(message.content, bodyBudget),
              timestamp: message.timestamp,
            ))
        .toList(growable: false);
  }

  String _truncatePreservingEnds(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    if (maxLength < 8) return text.substring(text.length - maxLength);
    final firstLength = (maxLength - 1) ~/ 2;
    final lastLength = maxLength - firstLength - 1;
    return '${text.substring(0, firstLength)}…${text.substring(text.length - lastLength)}';
  }

  Map<String, String> _asModelMessage(ChatMessage message) => {
        'role': message.isUser ? 'user' : 'assistant',
        'content': message.content,
      };

  String _boundedTranscript(List<ChatMessage> messages, int budget) {
    final buffer = StringBuffer();
    for (final message in messages) {
      final remaining = budget - buffer.length;
      if (remaining <= 0) break;
      final bodyBudget =
          (remaining - 48).clamp(0, message.content.length).toInt();
      final body = message.content.length <= bodyBudget
          ? message.content
          : '${message.content.substring(0, bodyBudget)}…';
      buffer.writeln(
          '[${message.id}] ${message.isUser ? 'user' : 'assistant'}: $body');
    }
    return buffer.toString().trim();
  }
}
