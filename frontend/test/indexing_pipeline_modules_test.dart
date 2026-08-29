import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:team_chai_and_code/local_index_bridge.dart';
import 'package:team_chai_and_code/models/retrieved_evidence.dart';
import 'package:team_chai_and_code/services/retrieval_tool.dart';
import 'package:team_chai_and_code/services/scanner_service.dart';

class FixtureIndex implements LocalIndexClient {
  final List<Map<String, dynamic>> response;

  FixtureIndex(this.response);

  @override
  Future<Map<String, dynamic>> exportCsv() async =>
      {'path': 'catalog_export.csv', 'records': response.length};

  @override
  Future<Map<String, dynamic>> indexChatMemory(
          Map<String, dynamic> record) async =>
      {'id': record['id'], 'indexed': true};

  @override
  Future<Map<String, dynamic>> indexOcr(Map<String, dynamic> record) async =>
      {'id': record['id'], 'indexed': true};

  @override
  Future<Map<String, dynamic>> indexText(Map<String, dynamic> record) async =>
      {'id': record['id'], 'indexed': true};

  @override
  Future<List<Map<String, dynamic>>> search(RetrievalRequest request) async =>
      response;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, dynamic> fixture;
  const indexChannel = MethodChannel('teamChaiAndCode/local_index');
  const scannerChannel = MethodChannel('teamChaiAndCode/local_scanner');

  setUpAll(() async {
    fixture = Map<String, dynamic>.from(jsonDecode(
      await File('test/fixtures/indexing_pipeline_probe.json').readAsString(),
    ) as Map);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(indexChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(scannerChannel, null);
  });

  test('text, OCR, and chat JSON reach the correct native index methods',
      () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(indexChannel, (call) async {
      calls.add(call);
      final input = Map<String, dynamic>.from(call.arguments as Map);
      return {
        'id': input['id'],
        'indexed': true,
        'catalog_csv': 'catalog_export.csv'
      };
    });
    const bridge = LocalIndexBridge();

    await bridge
        .indexText(Map<String, dynamic>.from(fixture['text_ingest'] as Map));
    await bridge
        .indexOcr(Map<String, dynamic>.from(fixture['ocr_ingest'] as Map));
    await bridge.indexChatMemory(
        Map<String, dynamic>.from(fixture['chat_ingest'] as Map));

    expect(calls.map((call) => call.method),
        ['indexText', 'indexOcr', 'indexChatMemory']);
    expect((calls[0].arguments as Map)['source_uri'], startsWith('content://'));
    expect((calls[1].arguments as Map)['transcription'], contains('1,250'));
    expect((calls[2].arguments as Map)['source_uri'],
        startsWith('chat://session/'));
  });

  test('search JSON reaches AppSearch and preserves its typed response',
      () async {
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(indexChannel, (call) async {
      captured = call;
      return fixture['search_response'];
    });
    const bridge = LocalIndexBridge();
    final requestJson =
        Map<String, dynamic>.from(fixture['search_request'] as Map);
    final results = await bridge.search(RetrievalRequest(
      query: requestJson['q'] as String,
      limit: requestJson['limit'] as int,
      contentTypes: Set<String>.from(requestJson['content_types'] as List),
    ));

    expect(captured?.method, 'search');
    expect((captured?.arguments as Map)['content_types'], contains('pdf_ocr'));
    expect(results.single['identifier'], 'idx-text-001');
  });

  test('retrieval sends extracted context but keeps URI for the UI tile',
      () async {
    final raw = (fixture['search_response'] as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    final evidence = (await RetrievalTool(index: FixtureIndex(raw)).search(
      const RetrievalRequest(query: 'bucket list'),
    ))
        .single;
    final expected =
        Map<String, dynamic>.from(fixture['expected_model_context'] as Map);

    expect(evidence.toModelContext(), expected);
    expect(evidence.toModelContext(), isNot(contains('source_uri')));
    expect(evidence.toModelContext(), isNot(contains('open_uri')));
    expect(evidence.openUri, startsWith('content://'));
    expect(evidence.displayName, 'bucket-list.txt');
  });

  test('CSV export JSON returns the durable mapping path and row count',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(indexChannel, (call) async {
      expect(call.method, 'exportCsv');
      return fixture['csv_export_response'];
    });

    final result = await const LocalIndexBridge().exportCsv();
    expect(result['path'], endsWith('/catalog/catalog_export.csv'));
    expect(result['records'], 3);
  });

  test('persisted-source scan accepts background ingestion records', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(scannerChannel, (call) async {
      expect(call.method, 'scanPersisted');
      return fixture['background_scan_response'];
    });

    final records = await ScannerService.instance.scanPersistedSources();
    expect(records, hasLength(1));
    expect(records.single['source_uri'], startsWith('content://'));
    expect(records.single['transcription'], contains('Paris'));
  });
}
