import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class DownloadProgress {
  final int bytesReceived;
  final int totalBytes;
  final double progress; // 0.0 to 1.0
  final bool isCompleted;
  final bool isFailed;
  final String? errorMessage;

  const DownloadProgress({
    required this.bytesReceived,
    required this.totalBytes,
    required this.progress,
    this.isCompleted = false,
    this.isFailed = false,
    this.errorMessage,
  });

  String get percentageText => '${(progress * 100).toStringAsFixed(1)}%';
  String get downloadedSizeText {
    final receivedMb = (bytesReceived / (1024 * 1024)).toStringAsFixed(1);
    final totalMb = totalBytes > 0
        ? (totalBytes / (1024 * 1024)).toStringAsFixed(1)
        : 'Unknown';
    return '$receivedMb MB / $totalMb MB';
  }
}

class LocalModelManagerService {
  static final LocalModelManagerService instance =
      LocalModelManagerService._internal();

  LocalModelManagerService._internal();

  final Map<String, StreamController<DownloadProgress>> _downloadControllers =
      {};
  final Map<String, http.Client> _activeClients = {};
  final Map<String, String> _activeTempPaths = {};
  final Set<String> _cancelledDownloads = {};

  static const String _storagePrefix = 'local_model_downloaded_';
  static const String _jobPrefix = 'local_model_job_';

  Future<String> getModelsDirectoryPath() async {
    if (kIsWeb) return 'web_models';
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final modelsDir = Directory('${appDir.path}/models');
      if (!await modelsDir.exists()) {
        await modelsDir.create(recursive: true);
      }
      return modelsDir.path;
    } catch (e) {
      debugPrint('Error getting models directory: $e');
      return 'models';
    }
  }

  Future<String> getModelFilePath(String filename) async {
    final dir = await getModelsDirectoryPath();
    return '$dir/$filename';
  }

  Future<bool> isModelDownloaded(String modelId, String filename) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('$_storagePrefix$modelId') ?? false;
    }

    try {
      final filePath = await getModelFilePath(filename);
      final file = File(filePath);
      final exists = await file.exists();
      if (exists) {
        final length = await file.length();
        return length > 1024; // Ensure non-empty
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<int> getModelSize(String filename) async {
    if (kIsWeb) return 0;
    try {
      final filePath = await getModelFilePath(filename);
      final file = File(filePath);
      if (await file.exists()) {
        return await file.length();
      }
      return 0;
    } catch (_) {
      return 0;
    }
  }

  Stream<DownloadProgress> downloadModel({
    required String modelId,
    required String downloadUrl,
    required String filename,
  }) {
    if (_downloadControllers.containsKey(modelId)) {
      return _downloadControllers[modelId]!.stream;
    }

    final controller = StreamController<DownloadProgress>.broadcast();
    _downloadControllers[modelId] = controller;

    SharedPreferences.getInstance().then((prefs) => prefs.setString(
        '$_jobPrefix$modelId',
        jsonEncode({'url': downloadUrl, 'filename': filename})));

    _startDownload(modelId, downloadUrl, filename, controller);

    return controller.stream;
  }

  Future<void> _startDownload(
    String modelId,
    String downloadUrl,
    String filename,
    StreamController<DownloadProgress> controller,
  ) async {
    final client = http.Client();
    _activeClients[modelId] = client;

    try {
      final targetPath = await getModelFilePath(filename);
      final tempPath = '$targetPath.tmp';

      final tempFile = File(tempPath);
      _activeTempPaths[modelId] = tempPath;
      final resumeAt = await tempFile.exists() ? await tempFile.length() : 0;
      final request = http.Request('GET', Uri.parse(downloadUrl));
      if (resumeAt > 0) request.headers['Range'] = 'bytes=$resumeAt-';
      final response = await client.send(request);

      if (response.statusCode != 200 && response.statusCode != 206) {
        throw Exception('Server returned HTTP ${response.statusCode}');
      }

      final supportsResume = resumeAt > 0 && response.statusCode == 206;
      final initialBytes = supportsResume ? resumeAt : 0;
      final totalBytes = response.contentLength == null
          ? 0
          : response.contentLength! + initialBytes;
      int receivedBytes = initialBytes;
      final sink = tempFile.openWrite(
          mode: supportsResume ? FileMode.append : FileMode.write);

      await for (final chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        final progress = totalBytes > 0 ? (receivedBytes / totalBytes) : 0.5;

        controller.add(DownloadProgress(
          bytesReceived: receivedBytes,
          totalBytes: totalBytes,
          progress: progress.clamp(0.0, 1.0),
        ));
      }

      await sink.flush();
      await sink.close();

      // Rename temp file to target model file
      final finalFile = File(targetPath);
      if (await finalFile.exists()) {
        await finalFile.delete();
      }
      await tempFile.rename(targetPath);

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_jobPrefix$modelId');
      await prefs.setBool('$_storagePrefix$modelId', true);
      await prefs.setString('$_storagePrefix${modelId}_path', targetPath);

      controller.add(DownloadProgress(
        bytesReceived: receivedBytes,
        totalBytes: totalBytes,
        progress: 1.0,
        isCompleted: true,
      ));
    } catch (e) {
      if (_cancelledDownloads.remove(modelId)) return;
      debugPrint('Download error for $modelId: $e');
      controller.add(DownloadProgress(
        bytesReceived: 0,
        totalBytes: 0,
        progress: 0.0,
        isFailed: true,
        errorMessage: e.toString(),
      ));
    } finally {
      client.close();
      _activeClients.remove(modelId);
      _activeTempPaths.remove(modelId);
      _downloadControllers.remove(modelId);
      await controller.close();
    }
  }

  void cancelDownload(String modelId) {
    _cancelledDownloads.add(modelId);
    final tempPath = _activeTempPaths[modelId];
    if (_activeClients.containsKey(modelId)) {
      _activeClients[modelId]?.close();
      _activeClients.remove(modelId);
    }
    if (_downloadControllers.containsKey(modelId)) {
      _downloadControllers[modelId]?.add(const DownloadProgress(
        bytesReceived: 0,
        totalBytes: 0,
        progress: 0.0,
        isFailed: true,
        errorMessage: 'Download cancelled by user',
      ));
      _downloadControllers[modelId]?.close();
      _downloadControllers.remove(modelId);
    }
    SharedPreferences.getInstance().then((prefs) async {
      await prefs.remove('$_jobPrefix$modelId');
      if (tempPath != null) {
        final temp = File(tempPath);
        if (await temp.exists()) await temp.delete();
      }
    });
  }

  /// Resumes jobs persisted before the Flutter process was recreated.
  Future<void> resumePendingDownloads() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key
        in prefs.getKeys().where((key) => key.startsWith(_jobPrefix))) {
      final modelId = key.substring(_jobPrefix.length);
      try {
        final job = jsonDecode(prefs.getString(key)!) as Map<String, dynamic>;
        downloadModel(
          modelId: modelId,
          downloadUrl: job['url'] as String,
          filename: job['filename'] as String,
        );
      } catch (error) {
        debugPrint(
            'Ignoring invalid persisted model download $modelId: $error');
        await prefs.remove(key);
      }
    }
  }

  Future<void> deleteModel(String modelId, String filename) async {
    try {
      final filePath = await getModelFilePath(filename);
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_storagePrefix$modelId');
      await prefs.remove('$_storagePrefix${modelId}_path');
    } catch (e) {
      debugPrint('Error deleting model: $e');
    }
  }
}
