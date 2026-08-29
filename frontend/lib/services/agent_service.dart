import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/agent_action.dart';
import '../models/ai_model_config.dart';
import '../models/chat_message.dart';
import '../models/chat_session.dart';
import '../models/retrieved_evidence.dart';
import 'local_model_manager_service.dart';
import 'chat_memory_index_service.dart';
import 'chat_storage_service.dart';
import 'conversation_context_service.dart';
import 'retrieval_tool.dart';
import 'local_inference_service.dart';
import 'agent_tool_catalog.dart';
import 'device_tools_service.dart';

enum AgentBackendMode { openRouterDirect, flaskBackend, localOnDevice }

enum _AgentIntent { generalChat, fileSearch, toolRequest }

/// Coordinates model selection with the typed, provenance-preserving retrieval tool.
class AgentService {
  static final AgentService instance = AgentService._internal();

  factory AgentService.withRetrievalTool(RetrievalTool retrievalTool) =>
      AgentService._internal(retrievalTool: retrievalTool);

  AgentService._internal(
      {RetrievalTool? retrievalTool,
      ChatMemoryIndexService? chatMemoryIndex,
      ConversationContextService? contextService})
      : _retrievalTool = retrievalTool ?? RetrievalTool(),
        _chatMemoryIndex = chatMemoryIndex ?? ChatMemoryIndexService(),
        _contextService = contextService ?? ConversationContextService();

  final RetrievalTool _retrievalTool;
  final ChatMemoryIndexService _chatMemoryIndex;
  final ConversationContextService _contextService;
  final LocalInferenceService _localInference = LocalInferenceService();
  final DeviceToolsService _deviceTools = DeviceToolsService();
  final Map<String, List<RetrievedEvidence>> _evidenceByMessageId = {};
  AgentBackendMode backendMode = AgentBackendMode.openRouterDirect;
  String openRouterApiKey = '';
  String backendBaseUrl = 'http://10.0.2.2:5000';
  List<AIModelConfig> dynamicFreeModels =
      List.from(AIModelConfig.defaultFreeOpenRouterModels);

  List<RetrievedEvidence> evidenceFor(ChatMessage message) =>
      _evidenceByMessageId[message.id] ?? const [];

  static const String _apiKeyStorageKey = 'openrouter_api_key_v1';
  static const String _selectedModelKey = 'selected_ai_model_id_v1';

  Future<void> init() async {
    // Download jobs are persisted independently of the model sheet lifecycle.
    await LocalModelManagerService.instance.resumePendingDownloads();
    try {
      final prefs = await SharedPreferences.getInstance();
      openRouterApiKey = prefs.getString(_apiKeyStorageKey) ?? '';
    } catch (_) {}
    try {
      await _chatMemoryIndex
          .syncSessions(await ChatStorageService.instance.getSessions());
    } catch (error) {
      debugPrint('Initial chat-memory backfill failed: $error');
    }
  }

  Future<void> setOpenRouterApiKey(String key) async {
    openRouterApiKey = key.trim();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_apiKeyStorageKey, openRouterApiKey);
    } catch (_) {}
  }

  Future<void> saveSelectedModel(String modelId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_selectedModelKey, modelId);
    } catch (_) {}
  }

  Future<String?> getSavedSelectedModelId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_selectedModelKey);
      // Migrate the former Qwen default so existing installs use the new
      // Gamma 4 E4B Lite test target. A later explicit user selection is
      // persisted normally.
      if (saved == 'litert-community/qwen3-4b-mixed-int4' ||
          saved == 'litert-community/qwen2.5-1.5b-q8') {
        const gammaId = 'litert-community/gemma-4-E4B-it-litert-lm';
        await prefs.setString(_selectedModelKey, gammaId);
        return gammaId;
      }
      return saved;
    } catch (_) {
      return null;
    }
  }

  Future<List<AIModelConfig>> fetchFreeOpenRouterModels() async {
    try {
      final headers = <String, String>{};
      if (openRouterApiKey.isNotEmpty)
        headers['Authorization'] = 'Bearer $openRouterApiKey';
      final response = await http
          .get(Uri.parse('https://openrouter.ai/api/v1/models'),
              headers: headers)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return dynamicFreeModels;
      final models = (jsonDecode(response.body)['data'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map((item) {
            final pricing = item['pricing'] as Map<String, dynamic>?;
            final id = item['id'] as String? ?? '';
            final free = id.contains(':free') ||
                (pricing?['prompt'] == '0' || pricing?['prompt'] == 0) &&
                    (pricing?['completion'] == '0' ||
                        pricing?['completion'] == 0);
            if (!free || id.isEmpty) return null;
            final name = item['name'] as String? ?? id;
            return AIModelConfig(
              id: 'or-$id',
              openRouterModelId: id,
              name: name.contains('(free)') ? name : '$name (Free)',
              description:
                  item['description'] as String? ?? 'Free tier open model',
              provider: ModelProvider.openRouter,
              isFree: true,
              badge: 'Free OR',
            );
          })
          .whereType<AIModelConfig>()
          .toList();
      if (models.isNotEmpty) {
        dynamicFreeModels = models;
        AIModelConfig.availableModels = [
          ...AIModelConfig.localModels,
          ...models
        ];
      }
    } catch (error) {
      debugPrint('Unable to fetch free OpenRouter models: $error');
    }
    return dynamicFreeModels;
  }

  /// Returns the complete provider catalog. The UI starts with free models,
  /// then calls this only when the user searches for a specific model.
  Future<List<AIModelConfig>> fetchAllOpenRouterModels() async {
    try {
      final headers = <String, String>{};
      if (openRouterApiKey.isNotEmpty) {
        headers['Authorization'] = 'Bearer $openRouterApiKey';
      }
      final response = await http
          .get(Uri.parse('https://openrouter.ai/api/v1/models'),
              headers: headers)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return dynamicFreeModels;
      final data = (jsonDecode(response.body)['data'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>();
      return data
          .map((item) {
            final pricing = item['pricing'] as Map<String, dynamic>?;
            final id = item['id'] as String? ?? '';
            final free = id.contains(':free') ||
                (pricing?['prompt'] == '0' || pricing?['prompt'] == 0) &&
                    (pricing?['completion'] == '0' ||
                        pricing?['completion'] == 0);
            return AIModelConfig(
              id: 'or-$id',
              openRouterModelId: id,
              name: item['name'] as String? ?? id,
              description: item['description'] as String? ?? 'OpenRouter model',
              provider: ModelProvider.openRouter,
              isFree: free,
              badge: free ? 'Free Tier' : 'Paid • API key required',
            );
          })
          .where((model) => model.openRouterModelId.isNotEmpty)
          .toList();
    } catch (error) {
      debugPrint('Unable to fetch complete OpenRouter catalog: $error');
      return dynamicFreeModels;
    }
  }

  Future<ChatMessage> sendMessage({
    required ChatSession session,
    required String prompt,
    AIModelConfig? modelConfig,
    void Function(String partialText)? onStreamChunk,
  }) async {
    // Classify before touching the local index. General conversation (including
    // greetings) must not incur a memory/index lookup.
    final intent = _classifyIntent(prompt);
    final needsRetrieval = intent == _AgentIntent.fileSearch;
    List<RetrievedEvidence> evidence = const [];
    if (needsRetrieval) {
      try {
        await _chatMemoryIndex.syncSession(session);
        evidence = await _retrievalTool.search(RetrievalRequest(query: prompt));
      } on RetrievalException catch (error) {
        return _retrievalFailureMessage(error);
      } catch (error) {
        debugPrint('Local retrieval unavailable for this turn: $error');
      }
    }
    if (needsRetrieval && evidence.isEmpty) return _noEvidenceMessage(prompt);

    final activeModel = modelConfig ?? AIModelConfig.availableModels.first;
    if (activeModel.isLocal || backendMode == AgentBackendMode.localOnDevice) {
      return _runLocalModel(session, prompt, activeModel, evidence, intent);
    }
    if (backendMode == AgentBackendMode.flaskBackend)
      return _modelUnavailableMessage();
    if (openRouterApiKey.isEmpty) {
      return ChatMessage(
        id: 'msg-${DateTime.now().millisecondsSinceEpoch}',
        role: MessageRole.assistant,
        content:
            'An OpenRouter API key is required for the selected cloud model. No simulated device result was generated.',
        timestamp: DateTime.now(),
      );
    }
    try {
      final response =
          await _sendToOpenRouter(session, prompt, activeModel, evidence);
      _evidenceByMessageId[response.id] = evidence;
      await _indexAssistantResponse(session, response);
      return response;
    } catch (error) {
      debugPrint('OpenRouter direct call failed: $error');
      return ChatMessage(
        id: 'msg-${DateTime.now().millisecondsSinceEpoch}',
        role: MessageRole.assistant,
        content:
            'The selected cloud model failed: $error. No simulated device result was generated.',
        timestamp: DateTime.now(),
      );
    }
  }

  Future<ChatMessage> _runLocalModel(
      ChatSession session,
      String prompt,
      AIModelConfig model,
      List<RetrievedEvidence> evidence,
      _AgentIntent intent) async {
    final filename = model.filename ?? 'gemma-4-E4B-it.litertlm';
    final downloaded = await LocalModelManagerService.instance
        .isModelDownloaded(model.id, filename);
    if (!downloaded) {
      return ChatMessage(
        id: 'msg-${DateTime.now().millisecondsSinceEpoch}',
        role: MessageRole.assistant,
        content: _ensureEvidenceCitations(
            '${model.name} is not downloaded. Download it from the model selector to prepare on-device inference.',
            evidence),
        timestamp: DateTime.now(),
      );
    }
    try {
      final modelPath =
          await LocalModelManagerService.instance.getModelFilePath(filename);
      final conversation = _contextService.build(session);
      final history = conversation.messages
          .map((message) => '${message['role']}: ${message['content']}')
          .join('\n');
      final contextualPrompt = [
        'You are teamChai, a helpful on-device assistant.',
        if (intent == _AgentIntent.toolRequest)
          'This is a tool request. Use reasoning privately to select the safest tool. Return a single JSON object with keys tool, arguments, confirmation_required, and user_message. Never execute a destructive operation without confirmation.',
        if (intent == _AgentIntent.toolRequest)
          'Available tools:\n${AgentToolCatalog.asPrompt()}',
        if (history.isNotEmpty) 'Conversation history:\n$history',
        'Current user request:\n$prompt',
      ].join('\n\n');
      final response = await _localInference.generate(
        modelPath: modelPath,
        prompt: _promptWithEvidence(contextualPrompt, evidence),
        enableThinking: intent == _AgentIntent.toolRequest,
      );
      final plannedAction = intent == _AgentIntent.toolRequest
          ? _parseToolAction(response)
          : null;
      final message = ChatMessage(
        id: 'msg-${DateTime.now().millisecondsSinceEpoch}',
        role: MessageRole.assistant,
        content: _ensureEvidenceCitations(
            _sanitizeModelResponse(response), evidence),
        timestamp: DateTime.now(),
        thoughtProcess: 'Model: ${model.name} (LiteRT-LM on device)',
        actions: plannedAction == null ? null : [plannedAction],
      );
      _evidenceByMessageId[message.id] = evidence;
      await _indexAssistantResponse(session, message);
      return message;
    } catch (error) {
      debugPrint('Local LiteRT-LM inference failed: $error');
      return ChatMessage(
        id: 'msg-${DateTime.now().millisecondsSinceEpoch}',
        role: MessageRole.assistant,
        content: _ensureEvidenceCitations(
            'The downloaded local model could not be initialized: $error',
            evidence),
        timestamp: DateTime.now(),
        thoughtProcess: 'LiteRT-LM initialization or generation failed.',
      );
    }
  }

  Future<ChatMessage> _sendToOpenRouter(ChatSession session, String prompt,
      AIModelConfig model, List<RetrievedEvidence> evidence) async {
    final context = _contextService.build(session);
    final messages = <Map<String, String>>[
      {
        'role': 'system',
        'content':
            'You are teamChai, a smartphone assistant. Never claim to have searched a file or read device content without the verified evidence supplied in the user turn. Use only supplied extracted context for file facts and cite the supplied index_id when appropriate. Local file paths and original files are UI-only and are never model input.'
      },
      ...context.messages,
      {'role': 'user', 'content': _promptWithEvidence(prompt, evidence)},
    ];
    final response = await http
        .post(Uri.parse('https://openrouter.ai/api/v1/chat/completions'),
            headers: {
              'Authorization': 'Bearer $openRouterApiKey',
              'Content-Type': 'application/json',
              'HTTP-Referer': 'https://teamchaiandcode.local',
              'X-Title': 'teamChaiAndCode Mobile Agent',
            },
            body: jsonEncode(
                {'model': model.openRouterModelId, 'messages': messages}))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200)
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    final choices =
        jsonDecode(response.body)['choices'] as List<dynamic>? ?? [];
    final reply = choices.isEmpty
        ? 'The model returned no content.'
        : (choices.first['message']['content'] as String? ??
            'The model returned no content.');
    return ChatMessage(
      id: 'msg-${DateTime.now().millisecondsSinceEpoch}',
      role: MessageRole.assistant,
      content:
          _ensureEvidenceCitations(_sanitizeModelResponse(reply), evidence),
      timestamp: DateTime.now(),
      thoughtProcess: 'Model: ${model.openRouterModelId} (OpenRouter)',
    );
  }

  Future<void> _indexAssistantResponse(
      ChatSession session, ChatMessage response) async {
    try {
      await _chatMemoryIndex.indexMessage(session, response);
    } catch (error) {
      debugPrint('Assistant chat-memory indexing failed: $error');
    }
  }

  _AgentIntent _classifyIntent(String prompt) {
    final normalized = prompt.trim();
    if (normalized.isEmpty) return _AgentIntent.generalChat;
    final isToolRequest = RegExp(
            r'\b(create|set|add|remind|reminder|move|rename|delete|remove|organize|sort|restore|save|update|upsert)\b',
            caseSensitive: false)
        .hasMatch(normalized);
    if (isToolRequest) return _AgentIntent.toolRequest;
    final isFileQuery = RegExp(
            r'\b(find|search|look up|show|list|document|file|pdf|photo|image|scan|aadhaar|receipt|ocr)\b',
            caseSensitive: false)
        .hasMatch(normalized);
    return isFileQuery ? _AgentIntent.fileSearch : _AgentIntent.generalChat;
  }

  AgentAction? _parseToolAction(String response) {
    try {
      final match = RegExp(r'\{[\s\S]*\}').firstMatch(response);
      if (match == null) return null;
      final json = jsonDecode(match.group(0)!) as Map<String, dynamic>;
      final tool = json['tool']?.toString() ?? '';
      final definition = AgentToolCatalog.byName(tool);
      if (definition == null) return null;
      final args = Map<String, dynamic>.from(json['arguments'] as Map? ?? {});
      return AgentAction(
        id: 'action-${DateTime.now().millisecondsSinceEpoch}',
        type: definition.name,
        title: definition.name.replaceAll('_', ' ').toUpperCase(),
        description: json['user_message']?.toString() ?? definition.description,
        permissionLevel: definition.permission,
        parameters: args,
      );
    } catch (_) {
      return null;
    }
  }

  /// Remove model-only reasoning and transport preambles before rendering.
  String _sanitizeModelResponse(String response) {
    var cleaned = response.trim();
    cleaned = cleaned.replaceAll(
        RegExp(r'<think>.*?(?:</think>|$)', caseSensitive: false, dotAll: true),
        '');
    cleaned = cleaned.replaceAll(
        RegExp(r'<analysis>.*?(?:</analysis>|$)',
            caseSensitive: false, dotAll: true),
        '');
    cleaned = cleaned.replaceFirst(
        RegExp(r'^\s*(assistant|answer|response)\s*:\s*', caseSensitive: false),
        '');
    return cleaned.trim();
  }

  String _promptWithEvidence(String prompt, List<RetrievedEvidence> evidence) {
    if (evidence.isEmpty) return prompt;
    return '$prompt\n\nVerified local retrieval evidence (index IDs and extracted context only; never infer or request the original file):\n'
        '${const JsonEncoder.withIndent('  ').convert(evidence.map((item) => item.toModelContext()).toList())}';
  }

  String _ensureEvidenceCitations(
      String response, List<RetrievedEvidence> evidence) {
    if (evidence.isEmpty ||
        evidence.any((item) => response.contains(item.identifier)))
      return response;
    return '$response\n\nSources retrieved for this answer:\n${evidence.map((item) => '- ${item.citation}').join('\n')}';
  }

  ChatMessage _noEvidenceMessage(String prompt) => ChatMessage(
      id: 'msg-search-empty-${DateTime.now().millisecondsSinceEpoch}',
      role: MessageRole.assistant,
      content:
          'I searched the local index, but found no matching authorised content for “$prompt”. I have not read or inferred details from a file.',
      timestamp: DateTime.now(),
      thoughtProcess: 'Local retrieval completed with 0 ranked results.');
  ChatMessage _retrievalFailureMessage(RetrievalException error) => ChatMessage(
      id: 'msg-search-error-${DateTime.now().millisecondsSinceEpoch}',
      role: MessageRole.assistant,
      content:
          'I could not search local content: ${error.message}. No file or OCR result was used.',
      timestamp: DateTime.now(),
      thoughtProcess: 'Local retrieval failed (${error.failure.name}).');
  ChatMessage _modelUnavailableMessage() => ChatMessage(
      id: 'msg-model-error-${DateTime.now().millisecondsSinceEpoch}',
      role: MessageRole.assistant,
      content:
          'The selected model backend is unavailable. I did not generate a simulated device result.',
      timestamp: DateTime.now());

  Future<bool> executeAction(AgentAction action) async {
    action.status = ActionStatus.executing;
    try {
      final outcome =
          await _deviceTools.execute(action.type, action.parameters);
      action.result = outcome;
      action.status = ActionStatus.completed;
      return true;
    } catch (error) {
      action.status = ActionStatus.failed;
      action.errorMessage = error.toString();
      return false;
    }
  }
}
