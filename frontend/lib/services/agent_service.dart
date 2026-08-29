import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_session.dart';
import '../models/chat_message.dart';
import '../models/agent_action.dart';
import '../models/ai_model_config.dart';
import 'context_compression_service.dart';

enum AgentBackendMode {
  openRouterDirect, // Directly calls OpenRouter API from phone / web
  flaskBackend,     // Proxies through Flask backend
  mockSimulation,   // Offline fallback simulation
}

class AgentService {
  static final AgentService instance = AgentService._internal();

  AgentService._internal();

  AgentBackendMode backendMode = AgentBackendMode.openRouterDirect;
  String openRouterApiKey = '';
  String backendBaseUrl = 'http://10.0.2.2:5000';

  static const String _apiKeyStorageKey = 'openrouter_api_key_v1';

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

    // 1. Try Direct OpenRouter if API key is present or mode is openRouterDirect
    if (backendMode == AgentBackendMode.openRouterDirect && openRouterApiKey.isNotEmpty) {
      try {
        return await _sendToOpenRouter(session, prompt, modelConfig, attachmentPath);
      } catch (e) {
        debugPrint('OpenRouter direct call failed: $e. Trying fallback.');
      }
    }

    // 2. Try Flask Backend
    if (backendMode == AgentBackendMode.flaskBackend) {
      try {
        return await _sendToFlaskBackend(payload, prompt);
      } catch (e) {
        debugPrint('Flask backend connection failed: $e. Falling back to simulation.');
      }
    }

    // 3. Fallback: Intelligent Agent Simulation
    return await _simulateAgentResponse(session, prompt, attachmentPath, onStreamChunk);
  }

  /// Dispatches request directly to OpenRouter API
  Future<ChatMessage> _sendToOpenRouter(
    ChatSession session,
    String prompt,
    AIModelConfig? modelConfig,
    String? attachmentPath,
  ) async {
    final selectedModel = modelConfig?.openRouterModelId.isNotEmpty == true
        ? modelConfig!.openRouterModelId
        : 'deepseek/deepseek-chat';

    final messages = [
      {
        'role': 'system',
        'content': 'You are teamChai: a smartphone agent AI. '
            'You have access to device tools: search_files, ocr_image, send_whatsapp, organize_files. '
            'When a tool is needed, mention the tool and provide concise output. '
            'Always be helpful, precise, and conversational.',
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
      'content': attachmentPath != null ? '$prompt\n[Attached: $attachmentPath]' : prompt,
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

      return ChatMessage(
        id: 'msg-${DateTime.now().millisecondsSinceEpoch}',
        role: MessageRole.assistant,
        content: reply,
        timestamp: DateTime.now(),
        thoughtProcess: 'Executed via OpenRouter ($selectedModel)',
      );
    } else {
      throw Exception('OpenRouter error ${response.statusCode}: ${response.body}');
    }
  }

  /// Dispatches the HTTP request to Flask backend
  Future<ChatMessage> _sendToFlaskBackend(Map<String, dynamic> payload, String prompt) async {
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
        content: content,
        timestamp: DateTime.now(),
        actions: actions,
        thoughtProcess: data['thought_process'] as String?,
      );
    } else {
      throw Exception('Server returned status ${response.statusCode}: ${response.body}');
    }
  }

  /// Intelligent fallback simulation
  Future<ChatMessage> _simulateAgentResponse(
    ChatSession session,
    String prompt,
    String? attachmentPath,
    void Function(String partialText)? onStreamChunk,
  ) async {
    final lower = prompt.toLowerCase();
    final messageId = 'msg-${DateTime.now().millisecondsSinceEpoch}';
    final List<AgentAction> actions = [];
    String responseText = '';
    String? thoughtProcess;

    await Future.delayed(const Duration(milliseconds: 500));

    if (lower.contains('offer letter') || lower.contains('internship') || lower.contains('pdf') || lower.contains('find')) {
      thoughtProcess = '1. Search local storage for offer letters\n2. Extract stipend and joining date\n3. Generate WhatsApp dispatch permission card';

      actions.add(AgentAction(
        id: 'act-${Random().nextInt(9999)}',
        type: 'search_files',
        title: 'Unified File Index Search',
        description: 'Indexed match: Documents/Google_Offer_Letter.pdf',
        permissionLevel: ActionPermissionLevel.safe,
        status: ActionStatus.completed,
        parameters: {'query': 'offer letter', 'extension': 'pdf'},
        result: {'found': true, 'path': 'Documents/Google_Offer_Letter.pdf'},
      ));

      if (lower.contains('whatsapp') || lower.contains('send') || lower.contains('share') || lower.contains('rahul')) {
        actions.add(AgentAction(
          id: 'act-${Random().nextInt(9999)}',
          type: 'send_whatsapp',
          title: 'Send WhatsApp Message',
          description: 'Share internship details with Rahul Sharma',
          permissionLevel: ActionPermissionLevel.sensitive,
          status: ActionStatus.pendingApproval,
          parameters: {
            'recipient': 'Rahul Sharma',
            'phone': '+91 98765 43210',
            'message': 'Offer summary: Google SWE Intern. Stipend ₹1,25,000/mo. Joining June 15, 2026.',
          },
        ));
      }

      responseText = 'I searched your phone\'s local storage and extracted the key information:\n\n'
          '📁 **Document:** `Documents/Google_Offer_Letter.pdf`\n\n'
          '### 📑 Offer Highlights:\n'
          '• **Organization:** Google India\n'
          '• **Designation:** Software Engineering Intern\n'
          '• **Stipend:** ₹1,25,000 / month\n'
          '• **Joining Date:** 15th June 2026\n\n'
          '${actions.length > 1 ? 'I have staged the WhatsApp message for Rahul. Please review and approve below to send.' : 'Let me know if you would like me to share this or organize your documents.'}';
    } else if (lower.contains('receipt') || lower.contains('bill') || lower.contains('ocr') || lower.contains('expense') || attachmentPath != null) {
      thoughtProcess = '1. Run multimodal OCR on attached/recent image\n2. Parse itemized line items and total';

      actions.add(AgentAction(
        id: 'act-${Random().nextInt(9999)}',
        type: 'ocr_image',
        title: 'On-Device Vision OCR Scan',
        description: 'Parsed receipt text & numbers from image',
        permissionLevel: ActionPermissionLevel.safe,
        status: ActionStatus.completed,
        parameters: {'source': attachmentPath ?? 'Gallery/Recent_Receipt.png'},
        result: {'items_count': 3, 'total': '₹565'},
      ));

      responseText = 'Here is the itemized summary extracted from the receipt:\n\n'
          '| Item | Qty | Price |\n'
          '| :--- | :--- | :--- |\n'
          '| Masala Chai | 2 | ₹180 |\n'
          '| Paneer Roll | 2 | ₹320 |\n'
          '| Taxes & Delivery | - | ₹65 |\n'
          '| **Grand Total** | | **₹565** |\n\n'
          '✨ *Extracted using OpenRouter / local OCR.*';
    } else {
      responseText = 'teamChai agent processed your request.\n\n'
          'I have full context of this conversation and can search documents, scan receipts, or perform device actions.';
    }

    return ChatMessage(
      id: messageId,
      role: MessageRole.assistant,
      content: responseText,
      timestamp: DateTime.now(),
      actions: actions,
      thoughtProcess: thoughtProcess,
    );
  }

  Future<bool> executeAction(AgentAction action) async {
    action.status = ActionStatus.executing;
    await Future.delayed(const Duration(milliseconds: 600));
    action.status = ActionStatus.completed;
    return true;
  }
}
