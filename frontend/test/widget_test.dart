// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:team_chai_and_code/main.dart';
import 'package:team_chai_and_code/widgets/evidence_card.dart';
import 'package:team_chai_and_code/widgets/grounded_state_banner.dart';
import 'package:team_chai_and_code/widgets/file_operation_preview.dart';
import 'package:team_chai_and_code/models/retrieved_evidence.dart';
import 'package:team_chai_and_code/models/file_operation_models.dart';

class FakePathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async => '.';
  @override
  Future<String?> getTemporaryPath() async => '.';
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    PathProviderPlatform.instance = FakePathProviderPlatform();
  });

  // ── Existing app smoke test ─────────────────────────────────────────────

  testWidgets('shows the chat welcome state', (WidgetTester tester) async {
    await tester.pumpWidget(const TeamChaiAndCodeApp());
    await tester.pump();
    expect(find.byType(TeamChaiAndCodeApp), findsOneWidget);
  });

  // ── V1: No upload picker present ────────────────────────────────────────

  testWidgets('V1: no + attachment button in input bar',
      (WidgetTester tester) async {
    await tester.pumpWidget(const TeamChaiAndCodeApp());
    await tester.pump();
    // Must not find the add_circle_outline icon that was the old attachment button
    expect(find.byIcon(Icons.add_circle_outline_rounded), findsNothing);
  });

  // ── V2: EvidenceCard available source ───────────────────────────────────

  testWidgets('V2: EvidenceCard shows Open Source when sourceUri set',
      (WidgetTester tester) async {
    const ev = RetrievedEvidence(
      identifier: 'ev-001',
      sourceUri: 'content://media/external/doc/1',
      openUri: 'content://media/external/doc/1',
      displayName: 'Aadhaar.pdf',
      mimeType: 'application/pdf',
      contentType: 'pdf_text',
      transcription: '',
      snippet: 'Aadhaar number 1234',
      page: 1,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: EvidenceCard(evidence: ev),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Open Source'), findsOneWidget);
    expect(find.text('Aadhaar.pdf'), findsOneWidget);
  });

  // ── V2: EvidenceCard unavailable source ────────────────────────────────

  testWidgets('V2: EvidenceCard shows Source Unavailable when sourceUri empty',
      (WidgetTester tester) async {
    const ev = RetrievedEvidence(
      identifier: 'ev-002',
      sourceUri: '',
      openUri: '',
      displayName: 'Unknown Doc',
      mimeType: 'application/pdf',
      contentType: 'pdf_text',
      transcription: '',
      snippet: 'Some snippet',
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: EvidenceCard(evidence: ev),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Source Unavailable'), findsOneWidget);
  });

  // ── V3: GroundedStateBanner noResults ──────────────────────────────────

  testWidgets('V3: GroundedStateBanner shows correct text for noResults',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GroundedStateBanner(state: GroundedState.noResults),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('No matching sources found on device.'), findsOneWidget);
  });

  // ── V3: GroundedStateBanner uncitedAnswer ──────────────────────────────

  testWidgets('V3: GroundedStateBanner shows uncited warning',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GroundedStateBanner(state: GroundedState.uncitedAnswer),
        ),
      ),
    );
    await tester.pump();
    expect(
      find.text(
          'Answer references device content but cites no source.'),
      findsOneWidget,
    );
  });

  // ── V6: FileOperationPreview renders manifest ──────────────────────────

  testWidgets('V6: FileOperationPreview shows operation badge and buttons',
      (WidgetTester tester) async {
    final manifest = PreviewManifest(
      operation: FileOperation.softDelete,
      candidates: [
        const CandidateFileSummary(
          sourceId: 'src-1',
          displayName: 'old_invoice.pdf',
          mimeType: 'application/pdf',
          matchingPredicates: ['content contains John'],
          providerCapabilities: ['trash'],
        ),
      ],
      candidateCount: 1,
      risks: ['Irreversible without trash support'],
      undoAvailable: true,
      generatedAt: DateTime(2026, 8, 29),
      manifestHash: 'abc123',
    );

    bool confirmed = false;
    bool cancelled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: FileOperationPreview(
              manifest: manifest,
              onCancel: () => cancelled = true,
              onConfirm: (_) => confirmed = true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Operation badge
    expect(find.text('SOFT DELETE'), findsOneWidget);
    // Candidate
    expect(find.text('old_invoice.pdf'), findsOneWidget);
    // Undo badge
    expect(find.text('Undo available'), findsOneWidget);
    // Risk chip
    expect(find.text('Irreversible without trash support'), findsOneWidget);
    // Buttons
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Confirm SOFT DELETE'), findsOneWidget);

    // Tap cancel
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(cancelled, isTrue);

    // Tap confirm
    await tester.tap(find.text('Confirm SOFT DELETE'));
    await tester.pump();
    expect(confirmed, isTrue);
  });
}
