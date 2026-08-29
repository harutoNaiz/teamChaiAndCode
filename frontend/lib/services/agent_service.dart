import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_session.dart';
import '../models/chat_message.dart';
import '../models/agent_action.dart';
import '../models/ai_model_config.dart';
import 'context_compression_service.dart';
import '../models/retrieved_evidence.dart';
import 'retrieval_tool.dart';

enum AgentBackendMode {
  openRouterDirect, // Directly calls OpenRouter API from phone / web
  flaskBackend,     // Proxies through Flask backend
  mockSimulation,   // Offline fallback simulation
}

class AgentService {
  static final AgentService instance = AgentService._internal();

  factory AgentService.withRetrievalTool(RetrievalTool retrievalTool) =>
      AgentService._internal(retrievalTool: retrievalTool);

  AgentService._internal({RetrievalTool? retrievalTool})
      : _retrievalTool = retrievalTool ?? RetrievalTool();

  final RetrievalTool _retrievalTool;

  AgentBackendMode backendMode = AgentBackendMode.openRouterDirect;
  String openRouterApiKey = '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';
  String backendBaseUrl = 'http://10.0.2.2:5000';

  static const String _apiKeyStorageKey = 'openrouter_api_key_v1';

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedKey = prefs.getString(_apiKeyStorageKey);
      if (storedKey != null && storedKey.isNotEmpty) {
        openRouterApiKey = storedKey;
      }
    } catch (_) {}
  }

  Future<void> setOpenRouterApiKey(String key) async {
    openRouterApiKey = key.trim();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_apiKeyStorageKey, openRouterApiKey);
    } catch (_) {}
  }

  /// Main entrypoint to send a message to the agent and receive a response
  Future<ChatMessage> sendMessage({
    required ChatSession session,
    required String prompt,
    String? attachmentPath,
    AIModelConfig? modelConfig,
    void Function(String partialText)? onStreamChunk,
  }) async {
    final payload = ContextCompressionService.instance.buildOptimizedPayload(
      session: session,
      newPrompt: prompt,
      attachmentPath: attachmentPath,
    );
    final needsRetrieval = _needsRetrieval(prompt);
    List<RetrievedEvidence> evidence = const [];

    try {
      evidence = await _retrievalTool.search(RetrievalRequest(query: prompt));
    } on RetrievalException catch (error) {
      if (needsRetrieval) {
        return _retrievalFailureMessage(error);
      }
      debugPrint('Local retrieval unavailable for this turn: ${error.message}');
    }

    if (needsRetrieval && evidence.isEmpty) {
      return _noEvidenceMessage(prompt);
    }

    // 1. Try Direct OpenRouter if API key is present or mode is openRouterDirect
    if (backendMode == AgentBackendMode.openRouterDirect && openRouterApiKey.isNotEmpty) {
      try {
        return await _sendToOpenRouter(
            session, prompt, modelConfig, attachmentPath, evidence);
      } catch (e) {
        debugPrint('OpenRouter direct call failed: $e. Trying fallback.');
      }
    }

    // 2. Try Flask Backend
    if (backendMode == AgentBackendMode.flaskBackend) {
      try {
        return await _sendToFlaskBackend(payload, prompt, evidence);
      } catch (e) {
        debugPrint('Flask backend connection failed: $e. Falling back to simulation.');
      }
    }

    // Never fabricate a device result when a model or backend is unavailable.
    return _modelUnavailableMessage();
  }

  /// Dispatches request directly to OpenRouter API
  Future<ChatMessage> _sendToOpenRouter(
    ChatSession session,
    String prompt,
    AIModelConfig? modelConfig,
    String? attachmentPath,
    List<RetrievedEvidence> evidence,
  ) async {
    final selectedModel = modelConfig?.openRouterModelId.isNotEmpty == true
        ? modelConfig!.openRouterModelId
        : 'deepseek/deepseek-chat';

    final messages = [
      {
        'role': 'system',
        'content': 'You are teamChai: a smartphone agent AI. '
            'You are teamChai, a smartphone assistant. You cannot claim to have searched '
            'a file or read device content unless evidence is provided below. Use only the '
            'provided snippets for file facts. Cite a supporting source as [Source: source_id]. '
            'If no evidence is provided, say that no local source was used.',
      },
    ];

    if (session.compressedSummary != null && session.compressedSummary!.isNotEmpty) {
      messages.add({
        'role': 'system',
        'content': 'Previous Compressed Context:\n${session.compressedSummary!}',
      });
    }

    for (final m in session.messages.take(6)) {
      messages.add({
        'role': m.isUser ? 'user' : 'assistant',
        'content': m.content,
      });
    }

    messages.add({
      'role': 'user',
      'content': _promptWithEvidence(prompt, attachmentPath, evidence),
    });

    final response = await http.post(
      Uri.parse('https://openrouter.ai/api/v1/chat/completions'),
      headers: {
        'Authorization': 'Bearer $openRouterApiKey',
        'Content-Type': 'application/json',
        'HTTP-Referer': 'https://teamchaiandcode.local',
        'X-Title': 'teamChaiAndCode Mobile Agent',
      },
      body: jsonEncode({
        'model': selectedModel,
        'messages': messages,
      }),
    ).timeout(const Duration(seconds: 25));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final choices = data['choices'] as List<dynamic>?;
      final reply = choices != null && choices.isNotEmpty
          ? (choices[0]['message']['content'] as String? ?? '')
          : 'Received empty response from OpenRouter.';

      final citedReply = _ensureEvidenceCitations(reply, evidence);
      return ChatMessage(
        id: 'msg-${DateTime.now().millisecondsSinceEpoch}',
        role: MessageRole.assistant,
        content: citedReply,
        timestamp: DateTime.now(),
        thoughtProcess: 'Executed via OpenRouter ($selectedModel)',
      );
    } else {
      throw Exception('OpenRouter error ${response.statusCode}: ${response.body}');
    }
  }

  /// Dispatches the HTTP request to Flask backend
  Future<ChatMessage> _sendToFlaskBackend(
      Map<String, dynamic> payload, String prompt, List<RetrievedEvidence> evidence) async {
    payload['retrieved_evidence'] = evidence.map((item) => item.toModelContext()).toList();
    final response = await http.post(
      Uri.parse('$backendBaseUrl/api/agent/chat'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final content = data['response'] as String? ?? 'Agent completed the request.';
      final actionsData = data['actions'] as List<dynamic>? ?? [];

      final actions = actionsData
          .map((a) => AgentAction.fromJson(Map<String, dynamic>.from(a)))
          .toList();

      return ChatMessage(
        id: 'msg-${DateTime.now().millisecondsSinceEpoch}',
        role: MessageRole.assistant,
        content: _ensureEvidenceCitations(content, evidence),
        timestamp: DateTime.now(),
        actions: actions,
        thoughtProcess: data['thought_process'] as String?,
      );
    } else {
      throw Exception('Server returned status ${response.statusCode}: ${response.body}');
    }
  }

  bool _needsRetrieval(String prompt) => RegExp(
          r'\b(find|search|look up|document|file|pdf|photo|image|scan|aadhaar|receipt|ocr)\b',
          caseSensitive: false)
      .hasMatch(prompt);

  String _promptWithEvidence(String prompt, String? attachmentPath,
      List<RetrievedEvidence> evidence) {
    final attachment = attachmentPath == null ? '' : '\n[Attached: $attachmentPath]';
    if (evidence.isEmpty) return '$prompt$attachment';
    return '$prompt$attachment\n\nVerified local retrieval evidence (use only this for device-file facts):\n'
        '${const JsonEncoder.withIndent('  ').convert(evidence.map((item) => item.toModelContext()).toList())}';
  }

  String _ensureEvidenceCitations(String response, List<RetrievedEvidence> evidence) {
    if (evidence.isEmpty || evidence.any((item) => response.contains(item.identifier))) {
      return response;
    }
    return '$response\n\nSources retrieved for this answer:\n${evidence.map((item) => '- ${item.citation}').join('\n')}';
  }

  ChatMessage _noEvidenceMessage(String prompt) => ChatMessage(
        id: 'msg-search-empty-${DateTime.now().millisecondsSinceEpoch}',
        role: MessageRole.assistant,
        content: 'I searched the local index, but found no matching authorised content for “$prompt”. '
            'I have not read or inferred details from a file.',
        timestamp: DateTime.now(),
        thoughtProcess: 'Local retrieval completed with 0 ranked results.',
      );

  ChatMessage _retrievalFailureMessage(RetrievalException error) => ChatMessage(
        id: 'msg-search-error-${DateTime.now().millisecondsSinceEpoch}',
        role: MessageRole.assistant,
        content: 'I could not search local content: ${error.message}. No file or OCR result was used.',
        timestamp: DateTime.now(),
        thoughtProcess: 'Local retrieval failed (${error.failure.name}).',
      );

  ChatMessage _modelUnavailableMessage() => ChatMessage(
        id: 'msg-model-error-${DateTime.now().millisecondsSinceEpoch}',
        role: MessageRole.assistant,
        content: 'The selected model is unavailable. I did not generate a simulated device result.',
        timestamp: DateTime.now(),
      );

  Future<bool> executeAction(AgentAction action) async {
    action.status = ActionStatus.executing;
    await Future.delayed(const Duration(milliseconds: 600));
    action.status = ActionStatus.completed;
    return true;
  }
}
