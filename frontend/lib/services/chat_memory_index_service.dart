import '../local_index_bridge.dart';
import '../models/chat_message.dart';
import '../models/chat_session.dart';

/// Indexes persisted chat text locally as provenance-bearing `chat_memory`.
class ChatMemoryIndexService {
  final LocalIndexClient _index;

  ChatMemoryIndexService({LocalIndexClient? index})
      : _index = index ?? const LocalIndexBridge();

  Future<void> syncSession(ChatSession session) async {
    final turns = session.messages
        .where((message) => message.content.trim().isNotEmpty)
        .map((message) =>
            '[${message.timestamp.toIso8601String()}] ${message.role.name}: ${message.content.trim()}')
        .join('\n');
    if (turns.trim().isEmpty) return;
    final uri = 'chat://session/${Uri.encodeComponent(session.id)}';
    await _index.indexChatMemory({
      'id': 'chat-${session.id}',
      'source_uri': uri,
      'display_name': session.title,
      'mime_type': 'text/markdown',
      'content_type': 'chat_memory',
      'transcription': turns,
      'modified_at': session.updatedAt.millisecondsSinceEpoch,
    });
  }

  Future<void> syncSessions(Iterable<ChatSession> sessions) async {
    for (final session in sessions) {
      await syncSession(session);
    }
  }

  Future<void> indexMessage(ChatSession session, ChatMessage message) async {
    if (message.content.trim().isEmpty) return;
    final uri =
        'chat://session/${Uri.encodeComponent(session.id)}/message/${Uri.encodeComponent(message.id)}';
    await _index.indexChatMemory({
      'id': 'chat-${session.id}-${message.id}',
      'source_uri': uri,
      'display_name': session.title,
      'mime_type': 'text/markdown',
      'content_type': 'chat_memory',
      'transcription': message.content,
      'modified_at': message.timestamp.millisecondsSinceEpoch,
    });
  }
}
