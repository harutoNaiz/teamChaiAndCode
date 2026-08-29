import 'package:flutter_test/flutter_test.dart';
import 'package:team_chai_and_code/local_index_bridge.dart';
import 'package:team_chai_and_code/models/chat_message.dart';
import 'package:team_chai_and_code/models/chat_session.dart';
import 'package:team_chai_and_code/models/retrieved_evidence.dart';
import 'package:team_chai_and_code/services/chat_memory_index_service.dart';

class RecordingIndex implements LocalIndexClient {
  final records = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>> indexChatMemory(Map<String, dynamic> record) async {
    records.add(record);
    return {'indexed': true};
  }
  @override Future<Map<String, dynamic>> indexOcr(Map<String, dynamic> record) async => {'indexed': true};
  @override Future<Map<String, dynamic>> indexText(Map<String, dynamic> record) async => {'indexed': true};
  @override Future<List<Map<String, dynamic>>> search(RetrievalRequest request) async => const [];
}

void main() {
  test('indexes every non-empty message with session/message provenance', () async {
    final session = ChatSession(id: 'session one', title: 'Planning', createdAt: DateTime(2026), updatedAt: DateTime(2026));
    session.addMessage(ChatMessage(id: 'm1', role: MessageRole.user, content: 'Remember the sprint date', timestamp: DateTime(2026)));
    session.addMessage(ChatMessage(id: 'm2', role: MessageRole.assistant, content: '', timestamp: DateTime(2026)));
    final index = RecordingIndex();

    await ChatMemoryIndexService(index: index).syncSession(session);

    expect(index.records, hasLength(1));
    expect(index.records.single['content_type'], 'chat_memory');
    expect(index.records.single['source_uri'], contains('chat://session/session%20one/message/m1'));
  });
}
