import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../local_index_bridge.dart';

class ScanSourceResult {
  final String status;
  final String? uri;
  final List<Map<String, dynamic>> records;
  final String? error;

  ScanSourceResult({
    required this.status,
    this.uri,
    this.records = const [],
    this.error,
  });

  bool get isSuccess => status == 'success' || status == 'indexed';
}

/// Service providing Android Storage Access Framework (SAF) folder/document discovery,
/// on-device OCR extraction, and feeding records to the local index.
class ScannerService {
  static final ScannerService instance = ScannerService._internal();

  ScannerService._internal();

  static const MethodChannel _scannerChannel =
      MethodChannel('teamChaiAndCode/local_scanner');
  static const LocalIndexBridge _indexBridge = LocalIndexBridge();

  static const String _scannedSourcesPrefKey = 'team_chai_scanned_sources_v1';

  /// Picks a folder on Android via SAF and indexes all discovered documents/photos.
  Future<ScanSourceResult> pickAndScanFolder() async {
    try {
      final rawResult = await _scannerChannel.invokeMapMethod<String, dynamic>('pickFolder');
      if (rawResult == null) {
        return ScanSourceResult(status: 'cancelled');
      }

      final status = rawResult['status'] as String? ?? 'unknown';
      final uri = rawResult['uri'] as String?;
      final rawRecords = rawResult['records'] as List<dynamic>? ?? [];

      final records = rawRecords
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();

      if (uri != null) {
        await _saveScannedSource(uri);
      }

      return ScanSourceResult(
        status: status,
        uri: uri,
        records: records,
      );
    } on PlatformException catch (e) {
      debugPrint('ScannerService.pickAndScanFolder error: $e');
      return ScanSourceResult(
        status: 'error',
        error: e.message ?? 'Unknown scanner error',
      );
    } catch (e) {
      return ScanSourceResult(
        status: 'error',
        error: e.toString(),
      );
    }
  }

  /// Picks a single document or photo on Android via SAF and runs OCR / indexing.
  Future<ScanSourceResult> pickAndScanDocument() async {
    try {
      final rawResult = await _scannerChannel.invokeMapMethod<String, dynamic>('pickDocument');
      if (rawResult == null) {
        return ScanSourceResult(status: 'cancelled');
      }

      final status = rawResult['status'] as String? ?? 'unknown';
      final uri = rawResult['uri'] as String?;
      final rawRecords = rawResult['records'] as List<dynamic>? ?? [];

      final records = rawRecords
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();

      return ScanSourceResult(
        status: status,
        uri: uri,
        records: records,
      );
    } on PlatformException catch (e) {
      return ScanSourceResult(
        status: 'error',
        error: e.message ?? 'Unknown scanner error',
      );
    }
  }

  /// Scans a specific content URI on demand.
  Future<List<Map<String, dynamic>>> scanUri(String uri) async {
    try {
      final rawResults = await _scannerChannel.invokeListMethod<dynamic>('scanUri', {'uri': uri}) ?? [];
      return rawResults.map((r) => Map<String, dynamic>.from(r as Map)).toList();
    } catch (e) {
      debugPrint('ScannerService.scanUri error: $e');
      return [];
    }
  }

  /// Opens the original source photo or document in the system viewer.
  Future<bool> openSourceUri(String uri) async {
    try {
      final result = await _scannerChannel.invokeMapMethod<String, dynamic>('openUri', {'uri': uri});
      return result?['opened'] == true;
    } catch (e) {
      // Fallback via index channel
      try {
        await _indexBridge.openUri(uri);
        return true;
      } catch (_) {
        return false;
      }
    }
  }

  Future<void> _saveScannedSource(String uri) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sources = prefs.getStringList(_scannedSourcesPrefKey) ?? [];
      if (!sources.contains(uri)) {
        sources.add(uri);
        await prefs.setStringList(_scannedSourcesPrefKey, sources);
      }
    } catch (_) {}
  }
}
