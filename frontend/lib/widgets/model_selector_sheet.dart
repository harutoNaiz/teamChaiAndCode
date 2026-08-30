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
  final Map<String, StreamSubscription<DownloadProgress>?>
      _downloadSubscriptions = {};
  final Map<String, DownloadProgress?> _currentProgress = {};

  final TextEditingController _apiKeyController =
      TextEditingController(text: AgentService.instance.openRouterApiKey);
  final TextEditingController _searchController = TextEditingController();

  List<AIModelConfig> _freeModels = [];
  List<AIModelConfig> _filteredFreeModels = [];
  bool _allModelsLoaded = false;
  bool _loadingAllModels = false;
  bool _isSyncingModels = false;

  @override
  void initState() {
    super.initState();
    _freeModels = List.from(AgentService.instance.dynamicFreeModels);
    _filteredFreeModels = List.from(_freeModels);
    _checkDownloadedModels();
  }

  @override
  void dispose() {
    for (final sub in _downloadSubscriptions.values) {
      sub?.cancel();
    }
    _apiKeyController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _filterModels(String query) async {
    if (query.trim().isNotEmpty && !_allModelsLoaded && !_loadingAllModels) {
      _loadingAllModels = true;
      final allModels = await AgentService.instance.fetchAllOpenRouterModels();
      if (!mounted) return;
      _freeModels = allModels;
      _allModelsLoaded = true;
      _loadingAllModels = false;
    }
    setState(() {
      if (query.trim().isEmpty) {
        _filteredFreeModels = List.from(_freeModels);
      } else {
        final q = query.toLowerCase();
        _filteredFreeModels = _freeModels.where((m) {
          return m.name.toLowerCase().contains(q) ||
              m.openRouterModelId.toLowerCase().contains(q) ||
              m.description.toLowerCase().contains(q);
        }).toList();
      }
    });
  }

  Future<void> _checkDownloadedModels() async {
    for (final model in AIModelConfig.localModels) {
      if (model.filename != null) {
        final downloaded =
            await LocalModelManagerService.instance.isModelDownloaded(
          model.id,
          model.filename!,
        );
        final size = await LocalModelManagerService.instance
            .getModelSize(model.filename!);
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
              content: Text(
                  '${model.name} downloaded successfully! Ready for on-device inference.'),
              backgroundColor: AppTheme.brandAccent,
            ),
          );
        } else if (progress.isFailed) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Download failed: ${progress.errorMessage ?? "Unknown error"}'),
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
    await LocalModelManagerService.instance
        .deleteModel(model.id, model.filename!);
    await _checkDownloadedModels();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${model.name} removed from device storage.')),
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

  Future<void> _syncFreeOpenRouterModels() async {
    setState(() => _isSyncingModels = true);
    final freeList = await AgentService.instance.fetchFreeOpenRouterModels();
    if (mounted) {
      setState(() {
        _isSyncingModels = false;
        _freeModels = freeList;
      });
      await _filterModels(_searchController.text);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Fetched ${_freeModels.length} free models from OpenRouter!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
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
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppTheme.darkTextTertiary.withOpacity(0.35)
                        : Colors.black.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Title
              Row(
                children: [
                  const Icon(Icons.tune_rounded,
                      color: AppTheme.brandAccent, size: 20),
                  const SizedBox(width: 10),
                  const Text(
                    'Model Library',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ===============================================================
              // SECTION 1: On-Device / Local Open-Source Models (LiteRT)
              // ===============================================================
              _buildSectionHeader('On-device · LiteRT', isDark),
              const SizedBox(height: 8),
              _buildLocalGroup(isDark),
              const SizedBox(height: 22),

              // ===============================================================
              // SECTION 2: Free OpenRouter Models (Dynamic Dropdown / Filter)
              // ===============================================================
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildSectionHeader(
                      _allModelsLoaded
                          ? 'OpenRouter · ${_freeModels.length} models'
                          : 'OpenRouter · ${_freeModels.length} free models',
                      isDark),
                  if (_isSyncingModels)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    InkWell(
                      onTap: _syncFreeOpenRouterModels,
                      child: const Row(
                        children: [
                          Icon(Icons.refresh_rounded,
                              size: 14, color: AppTheme.brandAccent),
                          SizedBox(width: 4),
                          Text(
                            'Refresh Free',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: AppTheme.brandAccent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),

              // Search Filter for Free Models
              Container(
                height: 42,
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkInset : const Color(0xFFF1F3F5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: isDark
                          ? AppTheme.hairline
                          : const Color(0xFFE5E7EB)),
                ),
                child: TextField(
                  controller: _searchController,
                  style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white : Colors.black87),
                  decoration: InputDecoration(
                    hintText: 'Search all OpenRouter models (free + paid)...',
                    hintStyle: TextStyle(
                        fontSize: 12.5,
                        color: isDark ? Colors.grey : Colors.black45),
                    prefixIcon:
                        const Icon(Icons.search, size: 16, color: Colors.grey),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  onChanged: (value) => _filterModels(value),
                ),
              ),
              const SizedBox(height: 8),

              // Free Models Dropdown List
              Container(
                constraints: const BoxConstraints(maxHeight: 260),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkElevated : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: isDark
                          ? AppTheme.hairline
                          : const Color(0xFFE5E7EB)),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: _filteredFreeModels.length,
                  separatorBuilder: (ctx, idx) => Divider(
                      height: 1,
                      thickness: 1,
                      indent: 14,
                      endIndent: 14,
                      color: isDark
                          ? AppTheme.hairline
                          : const Color(0xFFEEF0F2)),
                  itemBuilder: (ctx, idx) {
                    final model = _filteredFreeModels[idx];
                    final isSelected = widget.currentModel.id == model.id ||
                        widget.currentModel.openRouterModelId ==
                            model.openRouterModelId;

                    return Material(
                      color: isSelected
                          ? AppTheme.accentSubtle
                          : Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          widget.onSelectModel(model);
                          Navigator.pop(context);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 11),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      model.name,
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: isSelected
                                            ? FontWeight.w700
                                            : FontWeight.w600,
                                        color: isSelected
                                            ? AppTheme.brandAccent
                                            : (isDark
                                                ? AppTheme.darkTextPrimary
                                                : Colors.black87),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      model.openRouterModelId,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontFamily: 'monospace',
                                        color: isDark
                                            ? AppTheme.darkTextTertiary
                                            : Colors.black45,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              if (isSelected)
                                const Icon(Icons.check_rounded,
                                    color: AppTheme.brandAccent, size: 20)
                              else
                                const SizedBox(width: 20),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),

              // ===============================================================
              // SECTION 3: OpenRouter Settings (API Key & Config)
              // ===============================================================
              _buildSectionHeader('OpenRouter · configuration', isDark),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkElevated : const Color(0xFFF7F8FA),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: isDark
                          ? AppTheme.hairline
                          : const Color(0xFFE5E7EB)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Enter your OpenRouter API key for real-time model routing.',
                      style: TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: isDark
                              ? AppTheme.darkTextSecondary
                              : const Color(0xFF4B5563)),
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
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              fillColor:
                                  isDark ? AppTheme.darkInset : Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _saveApiKey,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.brandAccent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('Save',
                              style: TextStyle(fontWeight: FontWeight.w600)),
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
      title.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
        color: isDark ? AppTheme.darkTextTertiary : const Color(0xFF9098A3),
      ),
    );
  }

  // Apple-style grouped list of on-device models: one rounded card, hairline
  // separators, plain rows. Selection = a blue check; download = a basic
  // download glyph; in-flight = a tappable progress ring.
  Widget _buildLocalGroup(bool isDark) {
    final models = AIModelConfig.localModels;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkElevated : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: isDark ? AppTheme.hairline : const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          for (int i = 0; i < models.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                indent: 48,
                color: isDark ? AppTheme.hairline : const Color(0xFFEEF0F2),
              ),
            _localRow(models[i], isDark),
          ],
        ],
      ),
    );
  }

  Widget _localRow(AIModelConfig model, bool isDark) {
    final isSelected = widget.currentModel.id == model.id;
    final isDownloaded = _downloadedStates[model.id] ?? false;
    final sizeBytes = _modelSizes[model.id] ?? 0;
    final progress = _currentProgress[model.id];
    final isDownloading =
        progress != null && !progress.isCompleted && !progress.isFailed;

    final String subtitle;
    if (isDownloading) {
      subtitle = 'Downloading\u2026 ${progress.percentageText}';
    } else if (isDownloaded) {
      subtitle =
          'On-device \u00b7 ${(sizeBytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    } else {
      subtitle = model.badge;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (isDownloaded) {
            widget.onSelectModel(model);
            Navigator.pop(context);
          } else if (!isDownloading) {
            _startDownload(model);
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Icon(
                Icons.memory_rounded,
                size: 22,
                color: isSelected
                    ? AppTheme.brandAccent
                    : (isDark ? AppTheme.darkTextTertiary : Colors.black45),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      model.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                        color:
                            isDark ? AppTheme.darkTextPrimary : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: isDark
                            ? AppTheme.darkTextSecondary
                            : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _localTrailing(
                  model, isDark, isSelected, isDownloaded, isDownloading, progress),
            ],
          ),
        ),
      ),
    );
  }

  Widget _localTrailing(AIModelConfig model, bool isDark, bool isSelected,
      bool isDownloaded, bool isDownloading, DownloadProgress? progress) {
    if (isDownloading) {
      // Tappable progress ring with a stop glyph = cancel.
      return GestureDetector(
        onTap: () => _cancelDownload(model),
        child: SizedBox(
          width: 30,
          height: 30,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  value: (progress != null && progress.progress > 0)
                      ? progress.progress
                      : null,
                  strokeWidth: 2.2,
                  color: AppTheme.brandAccent,
                  backgroundColor:
                      isDark ? AppTheme.darkInset : const Color(0xFFE5E7EB),
                ),
              ),
              const Icon(Icons.stop_rounded,
                  size: 12, color: AppTheme.brandAccent),
            ],
          ),
        ),
      );
    }
    if (!isDownloaded) {
      // Basic download icon.
      return IconButton(
        icon: const Icon(Icons.arrow_circle_down_rounded, size: 26),
        color: AppTheme.brandAccent,
        tooltip: 'Download',
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
        onPressed: () => _startDownload(model),
      );
    }
    // Downloaded: basic select check + a subtle remove control.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isSelected)
          const Icon(Icons.check_rounded, color: AppTheme.brandAccent, size: 22)
        else
          const SizedBox(width: 22),
        const SizedBox(width: 2),
        IconButton(
          icon: const Icon(Icons.delete_outline_rounded, size: 19),
          color: isDark ? AppTheme.darkTextTertiary : Colors.black38,
          tooltip: 'Remove download',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          onPressed: () => _deleteModel(model),
        ),
      ],
    );
  }
}
