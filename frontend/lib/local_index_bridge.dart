import 'package:flutter/services.dart';
import 'models/retrieved_evidence.dart';

abstract class LocalIndexClient {
  Future<Map<String, dynamic>> indexText(Map<String, dynamic> record);
  Future<Map<String, dynamic>> indexOcr(Map<String, dynamic> record);
  Future<List<Map<String, dynamic>>> search(RetrievalRequest request);
}

class LocalIndexException implements Exception {
  final String code;
  final String message;

  const LocalIndexException(this.code, this.message);

  bool get isUnavailable =>
      code == 'index_unavailable' || code == 'index_closed' || code == 'unimplemented';
}

/// Non-UI boundary for indexing and searching Android device content.
class LocalIndexBridge implements LocalIndexClient {
  const LocalIndexBridge();

  static const MethodChannel _channel =
      MethodChannel('teamChaiAndCode/local_index');

  Future<Map<String, dynamic>> indexText(Map<String, dynamic> record) async {
    return _invokeMap('indexText', record);
  }

  Future<Map<String, dynamic>> indexOcr(Map<String, dynamic> record) async {
    return _invokeMap('indexOcr', record);
  }

  Future<List<Map<String, dynamic>>> search(RetrievalRequest request) async {
    try {
      final rawResults = await _channel.invokeListMethod<dynamic>(
              'search', request.toMap()) ??
          const [];
      return rawResults
          .map((result) => Map<String, dynamic>.from(result as Map))
          .toList(growable: false);
    } on PlatformException catch (error) {
      throw LocalIndexException(error.code, error.message ?? 'Local index failed');
    } on MissingPluginException {
      throw const LocalIndexException(
          'index_unavailable', 'On-device retrieval is unavailable on this platform.');
    }
  }

  Future<Map<String, dynamic>> _invokeMap(
      String method, Map<String, dynamic> record) async {
    try {
      final result =
          await _channel.invokeMapMethod<String, dynamic>(method, record);
      if (result == null) {
        throw const LocalIndexException(
            'empty_result', 'Index operation returned no result');
      }
      return Map<String, dynamic>.from(result);
    } on PlatformException catch (error) {
      throw LocalIndexException(error.code, error.message ?? 'Local index failed');
    }
  }
}
