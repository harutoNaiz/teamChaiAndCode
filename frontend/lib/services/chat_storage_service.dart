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
        _cache = [];
        await _persistToDisk();
      } else {
        final List<dynamic> decoded = jsonDecode(jsonString);
        _cache = decoded.map((item) => ChatSession.fromJson(Map<String, dynamic>.from(item))).toList();
      }
    } catch (e) {
      debugPrint('Error loading chat sessions: $e');
      _cache = [];
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
    return [];
  }
}
