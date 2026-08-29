import 'dart:async';
import 'package:flutter/material.dart';
import '../models/ai_model_config.dart';
import '../services/local_model_manager_service.dart';
import '../services/agent_service.dart';
import '../theme/app_theme.dart';

class ModelSelectorSheet extends StatefulWidget {
  final AIModelConfig currentModel;
  final Function(AIModelConfig model) onSelectModel;

  const ModelSelectorSheet({
    super.key,
    required this.currentModel,
    required this.onSelectModel,
  });

  static Future<void> show(
    BuildContext context, {
    required AIModelConfig currentModel,
    required Function(AIModelConfig model) onSelectModel,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => ModelSelectorSheet(
        currentModel: currentModel,
        onSelectModel: onSelectModel,
      ),
    );
  }

  @override
  State<ModelSelectorSheet> createState() => _ModelSelectorSheetState();
}

class _ModelSelectorSheetState extends State<ModelSelectorSheet> {
  final Map<String, bool> _downloadedStates = {};
  final Map<String, int> _modelSizes = {};
  final Map<String, StreamSubscription<DownloadProgress>?> _downloadSubscriptions = {};
  final Map<String, DownloadProgress?> _currentProgress = {};

  final TextEditingController _apiKeyController =
      TextEditingController(text: AgentService.instance.openRouterApiKey);
  bool _isSyncingModels = false;

  @override
  void initState() {
    super.initState();
    _checkDownloadedModels();
  }

  @override
  void dispose() {
    for (final sub in _downloadSubscriptions.values) {
      sub?.cancel();
    }
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _checkDownloadedModels() async {
    for (final model in AIModelConfig.localModels) {
      if (model.filename != null) {
        final downloaded = await LocalModelManagerService.instance.isModelDownloaded(
          model.id,
          model.filename!,
        );
        final size = await LocalModelManagerService.instance.getModelSize(model.filename!);
        if (mounted) {
          setState(() {
            _downloadedStates[model.id] = downloaded;
            _modelSizes[model.id] = size;
          });
        }
      }
    }
  }

  void _startDownload(AIModelConfig model) {
    if (model.downloadUrl == null || model.filename == null) return;

    final stream = LocalModelManagerService.instance.downloadModel(
      modelId: model.id,
      downloadUrl: model.downloadUrl!,
      filename: model.filename!,
    );

    setState(() {
      _currentProgress[model.id] = const DownloadProgress(
        bytesReceived: 0,
        totalBytes: 0,
        progress: 0.0,
      );
    });

    _downloadSubscriptions[model.id]?.cancel();
    _downloadSubscriptions[model.id] = stream.listen((progress) {
      if (mounted) {
        setState(() {
          _currentProgress[model.id] = progress;
        });

        if (progress.isCompleted) {
          _checkDownloadedModels();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${model.name} downloaded successfully! Ready for on-device inference.'),
              backgroundColor: AppTheme.brandAccent,
            ),
          );
        } else if (progress.isFailed) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Download failed: ${progress.errorMessage ?? "Unknown error"}'),
              backgroundColor: AppTheme.dangerRed,
            ),
          );
        }
      }
    });
  }

  void _cancelDownload(AIModelConfig model) {
    LocalModelManagerService.instance.cancelDownload(model.id);
    setState(() {
      _currentProgress[model.id] = null;
    });
  }

  Future<void> _deleteModel(AIModelConfig model) async {
    if (model.filename == null) return;
    await LocalModelManagerService.instance.deleteModel(model.id, model.filename!);
    await _checkDownloadedModels();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${model.name} removed from storage.')),
      );
    }
  }

  Future<void> _saveApiKey() async {
    final key = _apiKeyController.text.trim();
    await AgentService.instance.setOpenRouterApiKey(key);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('OpenRouter API Key saved!')),
      );
      setState(() {});
    }
  }

  Future<void> _syncLiveOpenRouterModels() async {
    if (AgentService.instance.openRouterApiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an OpenRouter API key first')),
      );
      return;
    }

    setState(() => _isSyncingModels = true);
    final count = await AgentService.instance.fetchLiveOpenRouterModels();
    if (mounted) {
      setState(() => _isSyncingModels = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Synced $count live models from your OpenRouter account!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Pull Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Title
              Row(
                children: [
                  const Icon(Icons.memory_rounded, color: AppTheme.brandAccent, size: 22),
                  const SizedBox(width: 8),
                  const Text(
                    'Select AI Engine & Models',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ===============================================================
              // SECTION 1: On-Device / Local Open-Source Models (LiteRT)
              // ===============================================================
              _buildSectionHeader('📱 ON-DEVICE OPEN-SOURCE MODELS (LITERT / NPU)', isDark),
              const SizedBox(height: 8),
              ...AIModelConfig.localModels.map((model) => _buildLocalModelTile(model, isDark)),
              const SizedBox(height: 16),

              // ===============================================================
              // SECTION 2: OpenRouter Cloud Open-Weight Models
              // ===============================================================
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildSectionHeader('🌐 OPENROUTER OPEN-WEIGHT MODELS', isDark),
                  if (_isSyncingModels)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    InkWell(
                      onTap: _syncLiveOpenRouterModels,
                      child: const Text(
                        'Sync Live',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppTheme.brandAccent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              ...AIModelConfig.openRouterModels.map((model) => _buildOpenRouterTile(model, isDark)),
              const SizedBox(height: 16),

              // ===============================================================
              // SECTION 3: OpenRouter Settings (API Key & Config)
              // ===============================================================
              _buildSectionHeader('🔑 OPENROUTER CONFIGURATION', isDark),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF242424) : const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isDark ? AppTheme.darkBorder : const Color(0xFFE5E7EB)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Enter your OpenRouter API key for real-time model routing:',
                      style: TextStyle(fontSize: 12.5),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _apiKeyController,
                            obscureText: true,
                            style: const TextStyle(fontSize: 13),
                            decoration: InputDecoration(
                              hintText: 'sk-or-v1-...',
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              fillColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _saveApiKey,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.brandAccent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('Save', style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, bool isDark) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.5,
        color: isDark ? AppTheme.darkTextSecondary : const Color(0xFF6B7280),
      ),
    );
  }

  Widget _buildLocalModelTile(AIModelConfig model, bool isDark) {
    final isSelected = widget.currentModel.id == model.id;
    final isDownloaded = _downloadedStates[model.id] ?? false;
    final sizeBytes = _modelSizes[model.id] ?? 0;
    final progress = _currentProgress[model.id];
    final isDownloading = progress != null && !progress.isCompleted && !progress.isFailed;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: isSelected ? AppTheme.brandAccent.withOpacity(0.08) : (isDark ? const Color(0xFF262626) : Colors.white),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? AppTheme.brandAccent : (isDark ? AppTheme.darkBorder : const Color(0xFFE5E7EB)),
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.purple.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.memory_rounded, color: Colors.purpleAccent, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              model.name,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.purple.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              model.badge,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.purpleAccent,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        model.description,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? AppTheme.darkTextSecondary : const Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  const Icon(Icons.check_circle, color: AppTheme.brandAccent, size: 20),
              ],
            ),
            const SizedBox(height: 10),

            // Storage Location & Download Control
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.folder_special_outlined, size: 14, color: Colors.grey),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'App Internal Storage: models/${model.filename}',
                          style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.grey),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // State Actions
                  if (isDownloading) ...[
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Downloading: ${progress.percentageText}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            Text(progress.downloadedSizeText, style: const TextStyle(fontSize: 11.5, color: Colors.grey)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        LinearProgressIndicator(
                          value: progress.progress,
                          color: AppTheme.brandAccent,
                          backgroundColor: Colors.grey.withOpacity(0.2),
                        ),
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () => _cancelDownload(model),
                            icon: const Icon(Icons.close, size: 14, color: AppTheme.dangerRed),
                            label: const Text('Cancel Download', style: TextStyle(color: AppTheme.dangerRed, fontSize: 12)),
                          ),
                        ),
                      ],
                    ),
                  ] else if (isDownloaded) ...[
                    Row(
                      children: [
                        const Icon(Icons.check_circle_outline, color: AppTheme.brandAccent, size: 15),
                        const SizedBox(width: 6),
                        Text(
                          'Downloaded (${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB)',
                          style: const TextStyle(color: AppTheme.brandAccent, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        const Spacer(),
                        if (!isSelected)
                          ElevatedButton(
                            onPressed: () {
                              widget.onSelectModel(model);
                              Navigator.pop(context);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.brandAccent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              minimumSize: Size.zero,
                            ),
                            child: const Text('Select Model', style: TextStyle(fontSize: 12)),
                          ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 16, color: Colors.grey),
                          tooltip: 'Delete downloaded model file',
                          onPressed: () => _deleteModel(model),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ] else ...[
                    Row(
                      children: [
                        const Icon(Icons.info_outline, size: 14, color: Colors.orange),
                        const SizedBox(width: 6),
                        const Text('Not downloaded yet', style: TextStyle(fontSize: 12, color: Colors.orange)),
                        const Spacer(),
                        ElevatedButton.icon(
                          onPressed: () => _startDownload(model),
                          icon: const Icon(Icons.download_rounded, size: 15),
                          label: const Text('Download Model', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.brandAccent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            minimumSize: Size.zero,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOpenRouterTile(AIModelConfig model, bool isDark) {
    final isSelected = widget.currentModel.id == model.id;

    return InkWell(
      onTap: () {
        widget.onSelectModel(model);
        Navigator.pop(context);
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.brandAccent.withOpacity(0.08) : (isDark ? const Color(0xFF262626) : Colors.white),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppTheme.brandAccent : (isDark ? AppTheme.darkBorder : const Color(0xFFE5E7EB)),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.cloud_outlined, size: 18, color: Colors.blueAccent),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          model.name,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          model.badge,
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.blueAccent,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    model.description,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark ? AppTheme.darkTextSecondary : const Color(0xFF6B7280),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, color: AppTheme.brandAccent, size: 20),
          ],
        ),
      ),
    );
  }
}
