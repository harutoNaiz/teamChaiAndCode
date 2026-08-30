import 'package:flutter_test/flutter_test.dart';
import 'package:team_chai_and_code/models/retrieved_evidence.dart';

void main() {
  test('retrieval hit separates model context from tile metadata', () {
    final evidence = RetrievedEvidence.fromMap({
      'identifier': 'idx-probe-1',
      'source_uri': 'content://documents/probe.pdf',
      'open_uri': 'content://documents/probe.pdf',
      'display_name': 'probe.pdf',
      'mime_type': 'application/pdf',
      'content_type': 'pdf_ocr',
      'transcription': 'Paris is on the bucket list.',
      'snippet': 'Paris is on the bucket list.',
      'page': 1,
      'score': 0.91,
    });

    final modelContext = evidence.toModelContext();
    expect(modelContext['index_id'], 'idx-probe-1');
    expect(modelContext['extracted_context'], contains('Paris'));
    expect(modelContext, isNot(contains('source_uri')));
    expect(modelContext, isNot(contains('open_uri')));
    expect(evidence.openUri, 'content://documents/probe.pdf');
    expect(evidence.displayName, 'probe.pdf');
  });
}
