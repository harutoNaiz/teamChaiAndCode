/// Provenance-preserving evidence returned by the on-device retrieval tool.
class RetrievedEvidence {
  final String identifier;
  final String sourceUri;
  final String openUri;
  final String displayName;
  final String mimeType;
  final String contentType;
  final String transcription;
  final String snippet;
  final int? page;
  final double? ocrConfidence;
  final int? modifiedAt;
  final double? score;

  const RetrievedEvidence({
    required this.identifier,
    required this.sourceUri,
    required this.openUri,
    required this.displayName,
    required this.mimeType,
    required this.contentType,
    required this.transcription,
    required this.snippet,
    this.page,
    this.ocrConfidence,
    this.modifiedAt,
    this.score,
  });

  factory RetrievedEvidence.fromMap(Map<String, dynamic> value) {
    String requiredString(String key) {
      final item = value[key] as String?;
      if (item == null || item.trim().isEmpty) {
        throw FormatException('Retrieval result is missing $key');
      }
      return item;
    }

    return RetrievedEvidence(
      identifier: requiredString('identifier'),
      sourceUri: requiredString('source_uri'),
      openUri: requiredString('open_uri'),
      displayName: requiredString('display_name'),
      mimeType: requiredString('mime_type'),
      contentType: requiredString('content_type'),
      transcription: requiredString('transcription'),
      snippet: requiredString('snippet'),
      page: (value['page'] as num?)?.toInt(),
      ocrConfidence: (value['ocr_confidence'] as num?)?.toDouble(),
      modifiedAt: (value['modified_at'] as num?)?.toInt(),
      score: (value['score'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toModelContext() => {
        // The model receives the stable index/extraction identity and the
        // extracted text only. The local URI and filename remain UI metadata.
        'index_id': identifier,
        'content_type': contentType,
        if (page != null) 'page': page,
        'snippet': snippet,
      };

  String get citation =>
      '[Source: $displayName${page == null ? '' : ', page $page'} — $identifier]';
}

class RetrievalRequest {
  final String query;
  final int limit;
  final Set<String> contentTypes;
  final Set<String> mimeTypes;
  final String? sourceUri;

  const RetrievalRequest({
    required this.query,
    this.limit = 5,
    this.contentTypes = const {},
    this.mimeTypes = const {},
    this.sourceUri,
  });

  Map<String, dynamic> toMap() => {
        'q': query,
        'limit': limit,
        if (contentTypes.isNotEmpty) 'content_types': contentTypes.toList(),
        if (mimeTypes.isNotEmpty) 'mime_types': mimeTypes.toList(),
        if (sourceUri != null) 'source_uri': sourceUri,
      };
}

enum RetrievalFailure { unavailable, invalidRequest, failed }

class RetrievalException implements Exception {
  final RetrievalFailure failure;
  final String message;

  const RetrievalException(this.failure, this.message);

  @override
  String toString() => message;
}
