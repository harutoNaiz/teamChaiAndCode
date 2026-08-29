import 'package:flutter_test/flutter_test.dart';
import 'package:team_chai_and_code/local_index_bridge.dart';
import 'package:team_chai_and_code/models/chat_message.dart';
import 'package:team_chai_and_code/models/chat_session.dart';
import 'package:team_chai_and_code/models/retrieved_evidence.dart';
import 'package:team_chai_and_code/services/chat_memory_index_service.dart';

class RecordingIndex implements LocalIndexClient {
  final records = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>> indexChatMemory(
      Map<String, dynamic> record) async {
    records.add(record);
    return {'indexed': true};
  }

  @override
  Future<Map<String, dynamic>> indexOcr(Map<String, dynamic> record) async =>
      {'indexed': true};
  @override
  Future<Map<String, dynamic>> indexText(Map<String, dynamic> record) async =>
      {'indexed': true};
  @override
  Future<List<Map<String, dynamic>>> search(RetrievalRequest request) async =>
      const [];
  @override
  Future<Map<String, dynamic>> exportCsv() async =>
      {'path': 'test.csv', 'records': records.length};
}

void main() {
  test('indexes one complete chat chart per session', () async {
    final session = ChatSession(
        id: 'session one',
        title: 'Planning',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        selectedModelId: 'test-model');
    session.addMessage(ChatMessage(
        id: 'm1',
        role: MessageRole.user,
        content: 'Remember the sprint date',
        timestamp: DateTime(2026)));
    session.addMessage(ChatMessage(
        id: 'm2',
        role: MessageRole.assistant,
        content: '',
        timestamp: DateTime(2026)));
    final index = RecordingIndex();

    await ChatMemoryIndexService(index: index).syncSession(session);

    expect(index.records, hasLength(1));
    expect(index.records.single['content_type'], 'chat_memory');
    expect(index.records.single['source_uri'], 'chat://session/session%20one');
    expect(index.records.single['transcription'],
        contains('Remember the sprint date'));
  });

  test('backfills every locally retained session', () async {
    final first = ChatSession(
        id: 'first',
        title: 'First',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        selectedModelId: 'test-model');
    final second = ChatSession(
        id: 'second',
        title: 'Second',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        selectedModelId: 'test-model');
    first.addMessage(ChatMessage(
        id: 'one',
        role: MessageRole.user,
        content: 'First memory',
        timestamp: DateTime(2026)));
    second.addMessage(ChatMessage(
        id: 'two',
        role: MessageRole.user,
        content: 'Second memory',
        timestamp: DateTime(2026)));
    final index = RecordingIndex();

    await ChatMemoryIndexService(index: index).syncSessions([first, second]);

    expect(
        index.records.map((item) => item['source_uri']),
        containsAll([
          'chat://session/first',
          'chat://session/second',
        ]));
  });
}
