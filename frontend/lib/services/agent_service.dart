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
import 'retrieval_tool.dart';

enum AgentBackendMode { openRouterDirect, flaskBackend, localOnDevice }

/// Coordinates model selection with the typed, provenance-preserving retrieval tool.
class AgentService {
  static final AgentService instance = AgentService._internal();

  factory AgentService.withRetrievalTool(RetrievalTool retrievalTool) =>
      AgentService._internal(retrievalTool: retrievalTool);

  AgentService._internal({RetrievalTool? retrievalTool})
      : _retrievalTool = retrievalTool ?? RetrievalTool();

  final RetrievalTool _retrievalTool;
  AgentBackendMode backendMode = AgentBackendMode.openRouterDirect;
  String openRouterApiKey = '';
  String backendBaseUrl = 'http://10.0.2.2:5000';
  List<AIModelConfig> dynamicFreeModels =
      List.from(AIModelConfig.defaultFreeOpenRouterModels);

  static const String _apiKeyStorageKey = 'openrouter_api_key_v1';
  static const String _selectedModelKey = 'selected_ai_model_id_v1';

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      openRouterApiKey = prefs.getString(_apiKeyStorageKey) ?? '';
    } catch (_) {}
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
      return (await SharedPreferences.getInstance()).getString(_selectedModelKey);
    } catch (_) {
      return null;
    }
  }

  Future<List<AIModelConfig>> fetchFreeOpenRouterModels() async {
    try {
      final headers = <String, String>{};
      if (openRouterApiKey.isNotEmpty) headers['Authorization'] = 'Bearer $openRouterApiKey';
      final response = await http.get(Uri.parse('https://openrouter.ai/api/v1/models'), headers: headers)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return dynamicFreeModels;
      final models = (jsonDecode(response.body)['data'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map((item) {
            final pricing = item['pricing'] as Map<String, dynamic>?;
            final id = item['id'] as String? ?? '';
            final free = id.contains(':free') ||
                (pricing?['prompt'] == '0' || pricing?['prompt'] == 0) &&
                    (pricing?['completion'] == '0' || pricing?['completion'] == 0);
            if (!free || id.isEmpty) return null;
            final name = item['name'] as String? ?? id;
            return AIModelConfig(
              id: 'or-$id', openRouterModelId: id,
              name: name.contains('(free)') ? name : '$name (Free)',
              description: item['description'] as String? ?? 'Free tier open model',
              provider: ModelProvider.openRouter, isFree: true, badge: 'Free OR',
            );
          }).whereType<AIModelConfig>().toList();
      if (models.isNotEmpty) {
        dynamicFreeModels = models;
        AIModelConfig.availableModels = [...AIModelConfig.localModels, ...models];
      }
    } catch (error) {
      debugPrint('Unable to fetch free OpenRouter models: $error');
    }
    return dynamicFreeModels;
  }

  Future<ChatMessage> sendMessage({
    required ChatSession session,
    required String prompt,
    String? attachmentPath,
    AIModelConfig? modelConfig,
    void Function(String partialText)? onStreamChunk,
  }) async {
    final needsRetrieval = _needsRetrieval(prompt);
    List<RetrievedEvidence> evidence = const [];
    try {
      evidence = await _retrievalTool.search(RetrievalRequest(query: prompt));
    } on RetrievalException catch (error) {
      if (needsRetrieval) return _retrievalFailureMessage(error);
      debugPrint('Local retrieval unavailable for this turn: ${error.message}');
    }
    if (needsRetrieval && evidence.isEmpty) return _noEvidenceMessage(prompt);

    final activeModel = modelConfig ?? AIModelConfig.availableModels.first;
    if (activeModel.isLocal || backendMode == AgentBackendMode.localOnDevice) {
      return _localModelStatus(activeModel, evidence);
    }
    if (backendMode == AgentBackendMode.flaskBackend) return _modelUnavailableMessage();
    if (openRouterApiKey.isEmpty) {
      return ChatMessage(
        id: 'msg-${DateTime.now().millisecondsSinceEpoch}', role: MessageRole.assistant,
        content: 'An OpenRouter API key is required for the selected cloud model. No simulated device result was generated.',
        timestamp: DateTime.now(),
      );
    }
    try {
      return await _sendToOpenRouter(session, prompt, activeModel, attachmentPath, evidence);
    } catch (error) {
      debugPrint('OpenRouter direct call failed: $error');
      return ChatMessage(
        id: 'msg-${DateTime.now().millisecondsSinceEpoch}', role: MessageRole.assistant,
        content: 'The selected cloud model failed: $error. No simulated device result was generated.',
        timestamp: DateTime.now(),
      );
    }
  }

  Future<ChatMessage> _localModelStatus(AIModelConfig model, List<RetrievedEvidence> evidence) async {
    final downloaded = await LocalModelManagerService.instance.isModelDownloaded(
        model.id, model.filename ?? 'gemma-4-E4B-it.litertlm');
    final status = downloaded
        ? 'The local model is downloaded, but local chat inference is not wired yet.'
        : '${model.name} is not downloaded. Download it from the model selector to prepare on-device inference.';
    return ChatMessage(
      id: 'msg-${DateTime.now().millisecondsSinceEpoch}', role: MessageRole.assistant,
      content: _ensureEvidenceCitations('$status No generated answer was produced.', evidence),
      timestamp: DateTime.now(),
    );
  }

  Future<ChatMessage> _sendToOpenRouter(ChatSession session, String prompt,
      AIModelConfig model, String? attachmentPath, List<RetrievedEvidence> evidence) async {
    final messages = <Map<String, String>>[
      {'role': 'system', 'content': 'You are teamChai, a smartphone assistant. Never claim to have searched a file or read device content without the verified evidence supplied in the user turn. Use only supplied snippets for file facts and cite them as [Source: source_id].'},
      ...session.messages.take(6).map((message) => {
            'role': message.isUser ? 'user' : 'assistant', 'content': message.content,
          }),
      {'role': 'user', 'content': _promptWithEvidence(prompt, attachmentPath, evidence)},
    ];
    final response = await http.post(Uri.parse('https://openrouter.ai/api/v1/chat/completions'), headers: {
      'Authorization': 'Bearer $openRouterApiKey', 'Content-Type': 'application/json',
      'HTTP-Referer': 'https://teamchaiandcode.local', 'X-Title': 'teamChaiAndCode Mobile Agent',
    }, body: jsonEncode({'model': model.openRouterModelId, 'messages': messages}))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}: ${response.body}');
    final choices = jsonDecode(response.body)['choices'] as List<dynamic>? ?? [];
    final reply = choices.isEmpty ? 'The model returned no content.' :
        (choices.first['message']['content'] as String? ?? 'The model returned no content.');
    return ChatMessage(
      id: 'msg-${DateTime.now().millisecondsSinceEpoch}', role: MessageRole.assistant,
      content: _ensureEvidenceCitations(reply, evidence), timestamp: DateTime.now(),
      thoughtProcess: 'Model: ${model.openRouterModelId} (OpenRouter)',
    );
  }

  bool _needsRetrieval(String prompt) => RegExp(
      r'\b(find|search|look up|document|file|pdf|photo|image|scan|aadhaar|receipt|ocr)\b',
      caseSensitive: false).hasMatch(prompt);

  String _promptWithEvidence(String prompt, String? attachmentPath, List<RetrievedEvidence> evidence) {
    if (evidence.isEmpty) return '$prompt${attachmentPath == null ? '' : '\n[Attached: $attachmentPath]'}';
    return '$prompt\n\nVerified local retrieval evidence (use only this for device-file facts):\n'
        '${const JsonEncoder.withIndent('  ').convert(evidence.map((item) => item.toModelContext()).toList())}';
  }

  String _ensureEvidenceCitations(String response, List<RetrievedEvidence> evidence) {
    if (evidence.isEmpty || evidence.any((item) => response.contains(item.identifier))) return response;
    return '$response\n\nSources retrieved for this answer:\n${evidence.map((item) => '- ${item.citation}').join('\n')}';
  }

  ChatMessage _noEvidenceMessage(String prompt) => ChatMessage(
      id: 'msg-search-empty-${DateTime.now().millisecondsSinceEpoch}', role: MessageRole.assistant,
      content: 'I searched the local index, but found no matching authorised content for “$prompt”. I have not read or inferred details from a file.',
      timestamp: DateTime.now(), thoughtProcess: 'Local retrieval completed with 0 ranked results.');
  ChatMessage _retrievalFailureMessage(RetrievalException error) => ChatMessage(
      id: 'msg-search-error-${DateTime.now().millisecondsSinceEpoch}', role: MessageRole.assistant,
      content: 'I could not search local content: ${error.message}. No file or OCR result was used.',
      timestamp: DateTime.now(), thoughtProcess: 'Local retrieval failed (${error.failure.name}).');
  ChatMessage _modelUnavailableMessage() => ChatMessage(
      id: 'msg-model-error-${DateTime.now().millisecondsSinceEpoch}', role: MessageRole.assistant,
      content: 'The selected model backend is unavailable. I did not generate a simulated device result.', timestamp: DateTime.now());

  Future<bool> executeAction(AgentAction action) async {
    action.status = ActionStatus.executing;
    await Future.delayed(const Duration(milliseconds: 500));
    action.status = ActionStatus.completed;
    return true;
  }
}
