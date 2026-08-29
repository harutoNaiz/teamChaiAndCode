import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:team_chai_and_code/local_index_bridge.dart';
import 'package:team_chai_and_code/models/retrieved_evidence.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const index = LocalIndexBridge();
  const runToken = 'chaiusb20260829';

  testWidgets('indexes and searches text and OCR records on Android', (tester) async {
    const notesUri =
        'content://com.android.externalstorage.documents/document/primary%3ADownload%2FChaiAndCodeTest%2Fmeeting-notes.txt';
    const imageUri =
        'content://com.android.externalstorage.documents/document/primary%3ADownload%2FChaiAndCodeTest%2Faadhaar-test-image.txt';

    await index.indexText({
      'id': '$runToken-notes-v1',
      'source_uri': notesUri,
      'display_name': 'meeting-notes.txt',
      'mime_type': 'text/plain',
      'content_type': 'text',
      'transcription':
          '$runToken project review is scheduled for 17 September 2026 at 10:30 AM.',
      'modified_at': 1789590600000,
    });

    await index.indexOcr({
      'id': '$runToken-image-v1',
      'source_uri': imageUri,
      'display_name': 'aadhaar-test-image.txt',
      'mime_type': 'image/jpeg',
      'content_type': 'image_ocr',
      'transcription':
          '$runToken Government of India Aadhaar Test Person 4321 8765 2109.',
      'ocr_confidence': 0.96,
      'modified_at': 1789590600000,
    });

    final textResults = await index.search(const RetrievalRequest(
      query: '$runToken project review',
    ));
    expect(textResults, isNotEmpty);
    expect(textResults.first['open_uri'], notesUri);
    expect(textResults.first['transcription'], contains('17 September 2026'));

    final ocrResults = await index.search(const RetrievalRequest(
      query: '$runToken Aadhaar',
    ));
    expect(ocrResults, isNotEmpty);
    expect(ocrResults.first['open_uri'], imageUri);
    expect(ocrResults.first['transcription'], contains('4321 8765 2109'));
  });

  testWidgets('re-indexing a source removes stale searchable text', (tester) async {
    const sourceUri =
        'content://com.android.externalstorage.documents/document/primary%3ADownload%2FChaiAndCodeTest%2Faction-items.txt';

    await index.indexText({
      'id': '$runToken-actions-v1',
      'source_uri': sourceUri,
      'display_name': 'action-items.txt',
      'mime_type': 'text/plain',
      'transcription': '$runToken staleorange submit the report on Monday.',
    });
    await index.indexText({
      'id': '$runToken-actions-v2',
      'source_uri': sourceUri,
      'display_name': 'action-items.txt',
      'mime_type': 'text/plain',
      'transcription': '$runToken freshmango submit the report on Friday.',
    });

    expect(await index.search(const RetrievalRequest(query: 'staleorange')), isEmpty);
    final freshResults = await index.search(const RetrievalRequest(query: 'freshmango'));
    expect(freshResults, hasLength(1));
    expect(freshResults.single['open_uri'], sourceUri);
  });

  testWidgets('preserves PDF provenance and bounds broad searches', (tester) async {
    const pdfUri =
        'content://com.android.externalstorage.documents/document/primary%3ADownload%2FChaiAndCodeTest%2Fcalendar.pdf';
    await index.indexText({
      'id': '$runToken-pdf-page-2',
      'source_uri': pdfUri,
      'display_name': 'calendar.pdf',
      'mime_type': 'application/pdf',
      'content_type': 'pdf_text',
      'transcription': '$runToken budget meeting is on 22 October 2026.',
      'page': 2,
    });

    final pdfResults = await index.search(const RetrievalRequest(
      query: '$runToken budget',
      contentTypes: {'pdf_text'},
    ));
    expect(pdfResults, isNotEmpty);
    expect(pdfResults.first['content_type'], 'pdf_text');
    expect(pdfResults.first['page'], 2);
    expect(pdfResults.first['open_uri'], pdfUri);

    for (var item = 0; item < 25; item++) {
      await index.indexText({
        'id': '$runToken-limit-$item',
        'source_uri': 'content://chai-test/limit-$item',
        'display_name': 'limit-$item.txt',
        'mime_type': 'text/plain',
        'transcription': '$runToken broadlimit result number $item',
      });
    }
    expect(await index.search(const RetrievalRequest(query: 'broadlimit', limit: 20)),
        hasLength(20));
  });

  testWidgets('opens source URI for indexed OCR photo result', (tester) async {
    const photoUri =
        'content://com.android.externalstorage.documents/document/primary%3ADCIM%2FAadhaar_Card_2026.jpg';

    await index.indexOcr({
      'id': '$runToken-aadhaar-photo',
      'source_uri': photoUri,
      'display_name': 'Aadhaar_Card_2026.jpg',
      'mime_type': 'image/jpeg',
      'content_type': 'image_ocr',
      'transcription':
          '$runToken Government of India Unique Identification Authority 1234 9876 5432',
      'ocr_confidence': 0.97,
      'modified_at': 1789590600000,
    });

    final searchResults = await index.search('$runToken Unique Identification');
    expect(searchResults, isNotEmpty);
    final top = searchResults.first;
    expect(top['open_uri'], photoUri);
    expect(top['content_type'], 'image_ocr');

    final openResult = await index.openUri(top['open_uri'] as String);
    expect(openResult['uri'], photoUri);
    expect(openResult.containsKey('opened'), isTrue);
  });
}

