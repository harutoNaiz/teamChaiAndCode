import '../local_index_bridge.dart';
import '../models/retrieved_evidence.dart';

/// Typed agent-tool boundary: a query and optional filters in, ranked evidence out.
class RetrievalTool {
  final LocalIndexClient _index;

  RetrievalTool({LocalIndexClient? index}) : _index = index ?? const LocalIndexBridge();

  Future<List<RetrievedEvidence>> search(RetrievalRequest request) async {
    final query = request.query.trim();
    if (query.isEmpty) {
      throw const RetrievalException(
          RetrievalFailure.invalidRequest, 'A retrieval query is required.');
    }
    if (request.limit < 1 || request.limit > 20) {
      throw const RetrievalException(
          RetrievalFailure.invalidRequest, 'Retrieval limit must be between 1 and 20.');
    }
    try {
      final results = await _index.search(request);
      return results.map(RetrievedEvidence.fromMap).toList(growable: false);
    } on RetrievalException {
      rethrow;
    } on LocalIndexException catch (error) {
      throw RetrievalException(error.isUnavailable
          ? RetrievalFailure.unavailable
          : RetrievalFailure.failed, error.message);
    } on FormatException catch (error) {
      throw RetrievalException(RetrievalFailure.failed, error.message);
    }
  }
}
