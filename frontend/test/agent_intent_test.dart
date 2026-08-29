import 'package:flutter_test/flutter_test.dart';
import 'package:team_chai_and_code/services/agent_service.dart';
import 'package:team_chai_and_code/services/retrieval_tool.dart';

void main() {
  final agent = AgentService.withRetrievalTool(RetrievalTool());

  test('routes note creation to tool request', () {
    expect(agent.classifyIntent('Create a note about the meeting'),
        AgentIntent.toolRequest);
  });

  test('routes file lookup to search', () {
    expect(
        agent.classifyIntent('Find the Aadhaar PDF'), AgentIntent.fileSearch);
  });

  test('routes greeting to general chat', () {
    expect(agent.classifyIntent('Hello'), AgentIntent.generalChat);
  });
}
