// V6: File-operation preview models.
// Flutter only renders these; it does NOT resolve URIs or execute operations.

enum FileOperation { list, move, rename, softDelete, restore }

extension FileOperationLabel on FileOperation {
  String get label => switch (this) {
        FileOperation.list => 'LIST',
        FileOperation.move => 'MOVE',
        FileOperation.rename => 'RENAME',
        FileOperation.softDelete => 'SOFT DELETE',
        FileOperation.restore => 'RESTORE',
      };
}

class CandidateFileSummary {
  final String sourceId;
  final String displayName;
  final String mimeType;
  final List<String> matchingPredicates;
  final List<String> providerCapabilities;

  const CandidateFileSummary({
    required this.sourceId,
    required this.displayName,
    required this.mimeType,
    required this.matchingPredicates,
    required this.providerCapabilities,
  });

  factory CandidateFileSummary.fromJson(Map<String, dynamic> j) =>
      CandidateFileSummary(
        sourceId: j['source_id'] as String? ?? '',
        displayName: j['display_name'] as String? ?? '',
        mimeType: j['mime_type'] as String? ?? '',
        matchingPredicates: (j['matching_predicates'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        providerCapabilities: (j['provider_capabilities'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
      );
}

class PreviewManifest {
  final FileOperation operation;
  final List<CandidateFileSummary> candidates;
  final int candidateCount;
  final String? destination;
  final List<String> risks;
  final bool undoAvailable;
  final DateTime generatedAt;
  final String manifestHash;

  const PreviewManifest({
    required this.operation,
    required this.candidates,
    required this.candidateCount,
    this.destination,
    required this.risks,
    required this.undoAvailable,
    required this.generatedAt,
    required this.manifestHash,
  });

  factory PreviewManifest.fromJson(Map<String, dynamic> j) => PreviewManifest(
        operation: FileOperation.values.firstWhere(
          (e) => e.name == j['operation'],
          orElse: () => FileOperation.list,
        ),
        candidates: (j['candidates'] as List<dynamic>?)
                ?.map((e) =>
                    CandidateFileSummary.fromJson(Map<String, dynamic>.from(e)))
                .toList() ??
            [],
        candidateCount: j['candidate_count'] as int? ?? 0,
        destination: j['destination'] as String?,
        risks: (j['risks'] as List<dynamic>?)?.map((e) => e as String).toList() ?? [],
        undoAvailable: j['undo_available'] as bool? ?? false,
        generatedAt:
            DateTime.tryParse(j['generated_at'] as String? ?? '') ?? DateTime.now(),
        manifestHash: j['manifest_hash'] as String? ?? '',
      );
}
