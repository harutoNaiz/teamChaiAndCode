import 'package:flutter_test/flutter_test.dart';
import 'package:team_chai_and_code/models/chat_message.dart';
import 'package:team_chai_and_code/models/chat_session.dart';
import 'package:team_chai_and_code/services/conversation_context_service.dart';

ChatSession sessionWithMessages(int count, {int chars = 20}) {
  final session = ChatSession(
    id: 'session-1', title: 'Context test', createdAt: DateTime(2026), updatedAt: DateTime(2026), selectedModelId: 'test-model',
  );
  for (var index = 0; index < count; index++) {
    session.addMessage(ChatMessage(
      id: 'message-$index', role: index.isEven ? MessageRole.user : MessageRole.assistant,
      content: '${'x' * chars}-$index', timestamp: DateTime(2026, 1, 1, 0, 0, index),
    ));
  }
  return session;
}

void main() {
  test('keeps the entire active session when it fits the model budget', () {
    final session = sessionWithMessages(20);
    final context = ConversationContextService().build(session, budget: 10000);

    expect(context.wasCompacted, isFalse);
    expect(context.messages, hasLength(20));
    expect(context.retainedMessageIds, hasLength(20));
    expect(context.messages.first['content'], endsWith('-0'));
  });

  test('uses stable-ID transcript and recent turns when session exceeds budget', () {
    final session = sessionWithMessages(24, chars: 300);
    final context = ConversationContextService().build(session, budget: 2048);

    expect(context.wasCompacted, isTrue);
    expect(context.messages.first['role'], 'system');
    expect(context.messages.first['content'], contains('[message-0]'));
    expect(context.messages.last['content'], endsWith('-23'));
    expect(context.retainedMessageIds, containsAll(['message-0', 'message-23']));
  });
}
