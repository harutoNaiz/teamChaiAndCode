import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/chat_session.dart';
import '../models/chat_message.dart';
import '../models/agent_action.dart';
import 'context_compression_service.dart';

enum AgentBackendMode {
  mockSimulation, // Works standalone on USB device without active backend server
  flaskBackend, // Connects to Flask REST / WebSocket backend
  localNpuSlm, // Future: Direct on-device ExecuTorch / ONNX NPU runtime
}

class AgentService {
  static final AgentService instance = AgentService._internal();

  AgentService._internal();

  AgentBackendMode backendMode = AgentBackendMode.mockSimulation;
  String backendBaseUrl =
      'http://10.0.2.2:5000'; // Default Android emulator host loopback

  /// Main entrypoint to send a message to the agent and receive a response
  Future<ChatMessage> sendMessage({
    required ChatSession session,
    required String prompt,
    String? attachmentPath,
    void Function(String partialText)? onStreamChunk,
  }) async {
    final payload = ContextCompressionService.instance.buildOptimizedPayload(
      session: session,
      newPrompt: prompt,
      attachmentPath: attachmentPath,
    );

    if (backendMode == AgentBackendMode.flaskBackend) {
      try {
        return await _sendToFlaskBackend(payload, prompt);
      } catch (e) {
        debugPrint(
            'Flask backend connection failed: $e. Falling back to simulation mode.');
      }
    }

    // Default or fallback: Mock intelligent agent simulation
    return await _simulateAgentResponse(
        session, prompt, attachmentPath, onStreamChunk);
  }

  /// Dispatches the real HTTP request to Flask backend
  Future<ChatMessage> _sendToFlaskBackend(
      Map<String, dynamic> payload, String prompt) async {
    final response = await http
        .post(
          Uri.parse('$backendBaseUrl/api/agent/chat'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final content =
          data['response'] as String? ?? 'Agent completed the request.';
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
      throw Exception(
          'Server returned status ${response.statusCode}: ${response.body}');
    }
  }

  /// Realistic on-device agent simulation for USB testing and demo
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

    // Simulate network/reasoning latency
    await Future.delayed(const Duration(milliseconds: 600));

    if (lower.contains('offer letter') ||
        lower.contains('internship') ||
        lower.contains('pdf') ||
        lower.contains('find')) {
      thoughtProcess =
          '1. Identify target document type: PDF / Offer letter\n2. Query local unified device index\n3. Summarize key metadata and check for outbound action';

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

      if (lower.contains('whatsapp') ||
          lower.contains('send') ||
          lower.contains('share')) {
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
            'message':
                'Offer summary: Google SWE Intern. Stipend ₹1,25,000/mo. Joining June 15, 2026.',
          },
        ));
      }

      responseText =
          'I searched your phone\'s local storage and extracted the key information:\n\n'
          '📁 **Document:** `Documents/Google_Offer_Letter.pdf`\n\n'
          '### 📑 Offer Highlights:\n'
          '• **Organization:** Google India\n'
          '• **Designation:** Software Engineering Intern\n'
          '• **Stipend:** ₹1,25,000 / month\n'
          '• **Joining Date:** 15th June 2026\n\n'
          '${actions.length > 1 ? 'I have staged the WhatsApp message for Rahul. Please review and approve below to send.' : 'Let me know if you would like me to share this or organize your documents.'}';
    } else if (lower.contains('receipt') ||
        lower.contains('bill') ||
        lower.contains('ocr') ||
        lower.contains('expense') ||
        attachmentPath != null) {
      thoughtProcess =
          '1. Run multimodal OCR on attached/recent image\n2. Parse itemized line items, quantities, and GST\n3. Structure tabular output';

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

      responseText =
          'Here is the itemized summary extracted from the receipt:\n\n'
          '| Item | Qty | Price |\n'
          '| :--- | :--- | :--- |\n'
          '| Masala Chai | 2 | ₹180 |\n'
          '| Paneer Roll | 2 | ₹320 |\n'
          '| Taxes & Delivery | - | ₹65 |\n'
          '| **Grand Total** | | **₹565** |\n\n'
          '✨ *Extracted in 120ms using local device OCR.*';
    } else if (lower.contains('clean') ||
        lower.contains('organize') ||
        lower.contains('download')) {
      thoughtProcess =
          '1. Scan Download folder for file extensions\n2. Create category buckets (Docs, Media, APKs)\n3. Prepare batch move operation';

      actions.add(AgentAction(
        id: 'act-${Random().nextInt(9999)}',
        type: 'organize_files',
        title: 'Organize Downloads Directory',
        description: 'Categorize 24 files into /Documents, /Images, and /APKs',
        permissionLevel: ActionPermissionLevel.medium,
        status: ActionStatus.completed,
        parameters: {'folder': 'Downloads/'},
      ));

      responseText =
          'I scanned your `Downloads/` directory and grouped 24 files:\n\n'
          '• 📄 **8 Documents** -> `Downloads/Documents/`\n'
          '• 🖼️ **11 Media Files** -> `Downloads/Images/`\n'
          '• 📦 **5 Installers** -> `Downloads/APKs/`\n\n'
          'Organization plan prepared and verified.';
    } else {
      responseText =
          'I am your smartphone agent powered by **teamChaiAndCode**.\n\n'
          'I have access to your local files, on-device OCR, and phone tools under your explicit permission.\n\n'
          'You can ask me to:\n'
          '• 🔎 *“Find my tax receipt PDF from last month”*\n'
          '• 📸 *“Scan this bill and calculate total expense”*\n'
          '• 📤 *“Summarize this document and draft a WhatsApp message”*';
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

  /// Executes an action (e.g. when user taps 'Approve' on a sensitive card)
  Future<bool> executeAction(AgentAction action) async {
    action.status = ActionStatus.executing;
    await Future.delayed(const Duration(milliseconds: 800));

    if (action.type == 'send_whatsapp') {
      action.status = ActionStatus.completed;
      action.result = {
        'sent': true,
        'timestamp': DateTime.now().toIso8601String()
      };
      return true;
    }

    action.status = ActionStatus.completed;
    return true;
  }
}
