import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_session.dart';
import '../models/chat_message.dart';
import '../models/agent_action.dart';

class ChatStorageService {
  static const String _storageKey = 'team_chai_chat_sessions_v1';
  static final ChatStorageService instance = ChatStorageService._internal();

  ChatStorageService._internal();

  List<ChatSession>? _cache;

  Future<List<ChatSession>> getSessions() async {
    if (_cache != null) {
      _sortSessions(_cache!);
      return List.from(_cache!);
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_storageKey);

      if (jsonString == null || jsonString.isEmpty) {
        // Initialize with realistic mock sessions for hackathon preview
        _cache = _getInitialSampleSessions();
        await _persistToDisk();
      } else {
        final List<dynamic> decoded = jsonDecode(jsonString);
        _cache = decoded.map((item) => ChatSession.fromJson(Map<String, dynamic>.from(item))).toList();
      }
    } catch (e) {
      debugPrint('Error loading chat sessions: $e');
      _cache = _getInitialSampleSessions();
    }

    _sortSessions(_cache!);
    return List.from(_cache!);
  }

  void _sortSessions(List<ChatSession> sessions) {
    sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<ChatSession?> getSessionById(String id) async {
    final sessions = await getSessions();
    try {
      return sessions.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveSession(ChatSession session) async {
    session.touch();
    final sessions = await getSessions();
    final index = sessions.indexWhere((s) => s.id == session.id);

    if (index >= 0) {
      sessions[index] = session;
    } else {
      sessions.insert(0, session);
    }

    _sortSessions(sessions);
    _cache = sessions;
    await _persistToDisk();
  }

  Future<void> deleteSession(String id) async {
    final sessions = await getSessions();
    sessions.removeWhere((s) => s.id == id);
    _cache = sessions;
    await _persistToDisk();
  }

  Future<void> renameSession(String id, String newTitle) async {
    final sessions = await getSessions();
    final index = sessions.indexWhere((s) => s.id == id);
    if (index >= 0) {
      sessions[index].title = newTitle;
      sessions[index].touch();
      _sortSessions(sessions);
      _cache = sessions;
      await _persistToDisk();
    }
  }

  Future<void> clearAllSessions() async {
    _cache = [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  Future<void> _persistToDisk() async {
    if (_cache == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(_cache!.map((s) => s.toJson()).toList());
      await prefs.setString(_storageKey, encoded);
    } catch (e) {
      debugPrint('Error persisting sessions: $e');
    }
  }

  List<ChatSession> _getInitialSampleSessions() {
    final now = DateTime.now();

    return [
      ChatSession(
        id: 'session-sample-1',
        title: 'Internship Offer Letter & WhatsApp',
        createdAt: now.subtract(const Duration(minutes: 15)),
        updatedAt: now.subtract(const Duration(minutes: 5)),
        messages: [
          ChatMessage(
            id: 'm1',
            role: MessageRole.user,
            content: 'Find my internship offer letter PDF, summarize the stipends & joining date, and send it to Rahul on WhatsApp.',
            timestamp: now.subtract(const Duration(minutes: 15)),
          ),
          ChatMessage(
            id: 'm2',
            role: MessageRole.assistant,
            content: 'I searched your device storage and located the document:\n\n'
                '**Document Found:** `Documents/Offer_Letters/Google_SWE_Intern_2026.pdf`\n\n'
                '### 📋 Summary:\n'
                '• **Role:** Software Engineering Intern\n'
                '• **Stipend:** ₹1,25,000 / month\n'
                '• **Joining Date:** 15th June 2026\n'
                '• **Location:** Bangalore Campus\n\n'
                'Please approve the action card below to dispatch the WhatsApp message to Rahul.',
            timestamp: now.subtract(const Duration(minutes: 14)),
            actions: [
              AgentAction(
                id: 'act-1',
                type: 'search_files',
                title: 'Search Device Storage',
                description: 'Found: Google_SWE_Intern_2026.pdf',
                permissionLevel: ActionPermissionLevel.safe,
                status: ActionStatus.completed,
                parameters: {'query': 'internship offer letter', 'extension': 'pdf'},
                result: {'matches': 1, 'path': 'Documents/Offer_Letters/Google_SWE_Intern_2026.pdf'},
              ),
              AgentAction(
                id: 'act-2',
                type: 'send_whatsapp',
                title: 'Send WhatsApp Message',
                description: 'Send internship summary to Rahul Sharma (+91 98765 43210)',
                permissionLevel: ActionPermissionLevel.sensitive,
                status: ActionStatus.pendingApproval,
                parameters: {
                  'contact': 'Rahul Sharma',
                  'phone': '+91 98765 43210',
                  'message': 'Hey Rahul! My Google SWE Intern stipend is ₹1.25L/mo and joining date is June 15, 2026.',
                },
              ),
            ],
          ),
        ],
      ),
      ChatSession(
        id: 'session-sample-2',
        title: 'Receipt OCR & Expense Summary',
        createdAt: now.subtract(const Duration(hours: 3)),
        updatedAt: now.subtract(const Duration(hours: 2)),
        messages: [
          ChatMessage(
            id: 'm3',
            role: MessageRole.user,
            content: 'Extract the items and total amount from the restaurant bill screenshot in my gallery.',
            timestamp: now.subtract(const Duration(hours: 3)),
          ),
          ChatMessage(
            id: 'm4',
            role: MessageRole.assistant,
            content: 'I analyzed `DCIM/Screenshots/Swiggy_Bill_Aug28.jpg` using on-device OCR:\n\n'
                '| Item | Quantity | Price |\n'
                '| :--- | :--- | :--- |\n'
                '| Masala Chai (Flask) | 2 | ₹180 |\n'
                '| Paneer Kathi Roll | 2 | ₹320 |\n'
                '| Taxes & Delivery | - | ₹65 |\n'
                '| **Total** | | **₹565** |\n\n'
                'Would you like me to log this ₹565 expense into your monthly expense sheet?',
            timestamp: now.subtract(const Duration(hours: 2)),
            actions: [
              AgentAction(
                id: 'act-3',
                type: 'ocr_image',
                title: 'On-Device OCR Scan',
                description: 'Extracted 4 line items from bill screenshot',
                permissionLevel: ActionPermissionLevel.safe,
                status: ActionStatus.completed,
                parameters: {'path': 'DCIM/Screenshots/Swiggy_Bill_Aug28.jpg'},
              ),
            ],
          ),
        ],
      ),
      ChatSession(
        id: 'session-sample-3',
        title: 'Organize Downloads Directory',
        createdAt: now.subtract(const Duration(days: 1, hours: 2)),
        updatedAt: now.subtract(const Duration(days: 1)),
        messages: [
          ChatMessage(
            id: 'm5',
            role: MessageRole.user,
            content: 'My downloads folder is full of random files. Can you organize them into folders by file type?',
            timestamp: now.subtract(const Duration(days: 1, hours: 2)),
          ),
          ChatMessage(
            id: 'm6',
            role: MessageRole.assistant,
            content: 'I analyzed 24 files in your `Downloads/` directory and grouped them:\n'
                '• 8 PDFs -> `Downloads/Documents/`\n'
                '• 11 Images -> `Downloads/Images/`\n'
                '• 5 APKs -> `Downloads/Installers/`\n\n'
                'Ready to execute file moves.',
            timestamp: now.subtract(const Duration(days: 1)),
          ),
        ],
      ),
    ];
  }
}
