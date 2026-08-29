import 'package:flutter/services.dart';
import '../local_index_bridge.dart';
import 'scanner_service.dart';

/// Narrow bridge for OS capabilities. The native side still enforces provider
/// support; Flutter never executes filesystem paths directly.
class DeviceToolsService {
  static const _channel = MethodChannel('teamChaiAndCode/device_tools');

  Future<Map<String, dynamic>> execute(
      String type, Map<String, dynamic> parameters) async {
    // These operations already have dedicated typed boundaries. Route them
    // through those boundaries instead of pretending they are generic OS
    // filesystem calls.
    if (type == 'ocr_image') {
      final uri = parameters['source_uri']?.toString();
      if (uri == null || uri.isEmpty) {
        throw ArgumentError('source_uri is required');
      }
      final records = await ScannerService.instance.scanUri(uri);
      return {
        'status': records.isEmpty ? 'no_extraction' : 'completed',
        'records': records
      };
    }
    if (type == 'upsert_file') {
      final record = <String, dynamic>{
        'id':
            parameters['id'] ?? 'file-${DateTime.now().millisecondsSinceEpoch}',
        'source_uri': parameters['uri'],
        'display_name': parameters['display_name'] ?? parameters['uri'],
        'mime_type': parameters['mime_type'] ?? 'text/plain',
        'content_type': 'text',
        'transcription': parameters['content'],
        if (parameters['modified_at'] != null)
          'modified_at': parameters['modified_at'],
      };
      return const LocalIndexBridge().indexText(record);
    }
    final result = await _channel.invokeMethod<dynamic>('execute', {
      'type': type,
      'parameters': parameters,
    });
    if (result is Map) return Map<String, dynamic>.from(result);
    throw StateError('Invalid response from device tool runtime.');
  }
}
