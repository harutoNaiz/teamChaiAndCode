import 'package:flutter/services.dart';

/// Non-UI boundary for indexing and searching Android device content.
class LocalIndexBridge {
  const LocalIndexBridge();

  static const MethodChannel _channel =
      MethodChannel('teamChaiAndCode/local_index');

  Future<Map<String, dynamic>> indexText(Map<String, dynamic> record) async {
    return _invokeMap('indexText', record);
  }

  Future<Map<String, dynamic>> indexOcr(Map<String, dynamic> record) async {
    return _invokeMap('indexOcr', record);
  }

  Future<List<Map<String, dynamic>>> search(String query) async {
    final rawResults =
        await _channel.invokeListMethod<dynamic>('search', {'q': query}) ??
            const [];
    return rawResults
        .map((result) => Map<String, dynamic>.from(result as Map))
        .toList();
  }

  Future<Map<String, dynamic>> _invokeMap(
      String method, Map<String, dynamic> record) async {
    final result =
        await _channel.invokeMapMethod<String, dynamic>(method, record);
    if (result == null) {
      throw PlatformException(
          code: 'empty_result', message: 'Index operation returned no result');
    }
    return Map<String, dynamic>.from(result);
  }
}
