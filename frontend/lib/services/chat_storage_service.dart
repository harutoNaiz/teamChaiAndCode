import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/chat_session.dart';
import '../models/chat_message.dart';
import '../models/agent_action.dart';
import '../widgets/grounded_state_banner.dart';

class ChatStorageService {
  static final ChatStorageService instance = ChatStorageService._internal();

  ChatStorageService._internal();

  List<ChatSession>? _cache;

  // In-memory fallback for web environment
  final Map<String, String> _webMarkdownStore = {};

  Future<String> getChatsDirectoryPath() async {
    if (kIsWeb) return 'web_chats';
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final chatsDir = Directory('${appDir.path}/chats');
      if (!await chatsDir.exists()) {
        await chatsDir.create(recursive: true);
      }
      return chatsDir.path;
    } catch (e) {
      debugPrint('Error accessing chats directory: $e');
      return 'chats';
    }
  }

  Future<String> _getSessionFilePath(String sessionId) async {
    final dir = await getChatsDirectoryPath();
    final sanitizedId = sessionId.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    return '$dir/$sanitizedId.md';
  }

  /// V4: Update indexing state for a session and persist.
  void setSessionIndexingState(String sessionId, SessionIndexingState state) {
    if (_cache == null) return;
    final idx = _cache!.indexWhere((s) => s.id == sessionId);
    if (idx >= 0) {
      _cache![idx].indexingState = state;
      _writeSessionToMarkdownFile(_cache![idx]);
    }
  }

  /// Converts a ChatSession into structured, human-readable Markdown (.md)
  String sessionToMarkdown(ChatSession session) {
    final buffer = StringBuffer();

    // 1. YAML Frontmatter Header
    buffer.writeln('---');
    buffer.writeln('id: ${session.id}');
    buffer.writeln('title: "${session.title.replaceAll('"', r'\"')}"');
    buffer.writeln('created_at: ${session.createdAt.toIso8601String()}');
    buffer.writeln('updated_at: ${session.updatedAt.toIso8601String()}');
    buffer.writeln('selected_model_id: ${session.selectedModelId}');
    // V4: persist indexing state
    buffer.writeln('indexing_state: ${session.indexingState.name}');
    if (session.compressedSummary != null &&
        session.compressedSummary!.isNotEmpty) {
      final escapedSummary = jsonEncode(session.compressedSummary);
      buffer.writeln('compressed_summary: $escapedSummary');
    }
    buffer.writeln('---');
    buffer.writeln();

    // 2. Body: Sequential Messages in Markdown Format
    for (final msg in session.messages) {
      buffer.writeln('### Message: ${msg.id}');
      buffer.writeln('- **Role:** ${msg.role.name}');
      buffer.writeln('- **Timestamp:** ${msg.timestamp.toIso8601String()}');
      // V1: No attachment fields written
      if (msg.thoughtProcess != null && msg.thoughtProcess!.isNotEmpty) {
        buffer
            .writeln('- **ThoughtProcess:** ${jsonEncode(msg.thoughtProcess)}');
      }
      if (msg.actions.isNotEmpty) {
        final actionsJson =
            jsonEncode(msg.actions.map((a) => a.toJson()).toList());
        buffer.writeln('- **Actions:** $actionsJson');
      }
      // V3: persist grounded state
      if (msg.groundedState != null) {
        buffer.writeln('- **GroundedState:** ${msg.groundedState!.name}');
      }
      if (msg.cloudModelName != null) {
        buffer.writeln('- **CloudModelName:** ${msg.cloudModelName}');
      }
      // V5: persist citation IDs
      if (msg.citationIds.isNotEmpty) {
        buffer.writeln(
            '- **CitationIds:** ${jsonEncode(msg.citationIds)}');
      }
      buffer.writeln();
      buffer.writeln(msg.content);
      buffer.writeln();
      buffer.writeln('---');
      buffer.writeln();
    }

    return buffer.toString();
  }

  /// Parses a Markdown (.md) document back into a ChatSession object
  ChatSession? sessionFromMarkdown(String content) {
    try {
      if (!content.startsWith('---')) return null;

      final headerEndIndex = content.indexOf('\n---', 3);
      if (headerEndIndex == -1) return null;

      final header = content.substring(3, headerEndIndex).trim();
      final body = content.substring(headerEndIndex + 4).trim();

      String id = 'session-${DateTime.now().millisecondsSinceEpoch}';
      String title = 'Chat';
      DateTime createdAt = DateTime.now();
      DateTime updatedAt = DateTime.now();
      String selectedModelId = 'litert-community/gemma-4-E4B-it-litert-lm';
      String? compressedSummary;
      SessionIndexingState indexingState = SessionIndexingState.notIndexed;

      // Parse Frontmatter
      for (final line in header.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.startsWith('id:')) {
          id = trimmed.substring(3).trim();
        } else if (trimmed.startsWith('title:')) {
          var t = trimmed.substring(6).trim();
          if (t.startsWith('"') && t.endsWith('"')) {
            t = t.substring(1, t.length - 1);
          }
          title = t;
        } else if (trimmed.startsWith('created_at:')) {
          createdAt =
              DateTime.tryParse(trimmed.substring(11).trim()) ?? createdAt;
        } else if (trimmed.startsWith('updated_at:')) {
          updatedAt =
              DateTime.tryParse(trimmed.substring(11).trim()) ?? updatedAt;
        } else if (trimmed.startsWith('selected_model_id:')) {
          selectedModelId = trimmed.substring(18).trim();
        } else if (trimmed.startsWith('indexing_state:')) {
          final raw = trimmed.substring(15).trim();
          indexingState = SessionIndexingState.values.firstWhere(
            (e) => e.name == raw,
            orElse: () => SessionIndexingState.notIndexed,
          );
        } else if (trimmed.startsWith('compressed_summary:')) {
          final raw = trimmed.substring(19).trim();
          try {
            compressedSummary = jsonDecode(raw) as String?;
          } catch (_) {
            compressedSummary = raw;
          }
        }
      }

      final session = ChatSession(
        id: id,
        title: title,
        createdAt: createdAt,
        updatedAt: updatedAt,
        selectedModelId: selectedModelId,
        compressedSummary: compressedSummary,
        indexingState: indexingState,
      );

      // Parse Message sections in Body
      final messageBlocks = body.split(RegExp(r'\n---\n'));
      for (final block in messageBlocks) {
        final trimmedBlock = block.trim();
        if (trimmedBlock.isEmpty ||
            !trimmedBlock.startsWith('### Message:')) continue;

        final lines = trimmedBlock.split('\n');
        String msgId = 'msg-${DateTime.now().millisecondsSinceEpoch}';
        MessageRole role = MessageRole.user;
        DateTime timestamp = DateTime.now();
        String? thoughtProcess;
        List<AgentAction> actions = [];
        GroundedState? groundedState;
        String? cloudModelName;
        List<String> citationIds = [];

        int bodyStartIndex = 0;
        for (int i = 0; i < lines.length; i++) {
          final l = lines[i].trim();
          if (l.startsWith('### Message:')) {
            msgId = l.substring(12).trim();
          } else if (l.startsWith('- **Role:**')) {
            final r = l.substring(11).trim().toLowerCase();
            role =
                r == 'assistant' ? MessageRole.assistant : MessageRole.user;
          } else if (l.startsWith('- **Timestamp:**')) {
            timestamp =
                DateTime.tryParse(l.substring(16).trim()) ?? timestamp;
          } else if (l.startsWith('- **ThoughtProcess:**')) {
            final raw = l.substring(21).trim();
            try {
              thoughtProcess = jsonDecode(raw) as String?;
            } catch (_) {
              thoughtProcess = raw;
            }
          } else if (l.startsWith('- **Actions:**')) {
            final raw = l.substring(14).trim();
            try {
              final List<dynamic> decoded = jsonDecode(raw);
              actions = decoded
                  .map((a) =>
                      AgentAction.fromJson(Map<String, dynamic>.from(a)))
                  .toList();
            } catch (_) {}
          } else if (l.startsWith('- **GroundedState:**')) {
            final raw = l.substring(20).trim();
            groundedState = GroundedState.values.firstWhere(
              (e) => e.name == raw,
              orElse: () => GroundedState.noResults,
            );
          } else if (l.startsWith('- **CloudModelName:**')) {
            cloudModelName = l.substring(21).trim();
          } else if (l.startsWith('- **CitationIds:**')) {
            final raw = l.substring(18).trim();
            try {
              final decoded = jsonDecode(raw) as List<dynamic>;
              citationIds = decoded.map((e) => e as String).toList();
            } catch (_) {}
          } else if (l.isEmpty && i > 1) {
            bodyStartIndex = i + 1;
            break;
          }
        }

        final msgContent = bodyStartIndex < lines.length
            ? lines.sublist(bodyStartIndex).join('\n').trim()
            : '';

        session.messages.add(ChatMessage(
          id: msgId,
          role: role,
          content: msgContent,
          timestamp: timestamp,
          thoughtProcess: thoughtProcess,
          actions: actions,
          groundedState: groundedState,
          cloudModelName: cloudModelName,
          citationIds: citationIds,
        ));
      }

      return session;
    } catch (e) {
      debugPrint('Error parsing markdown session: $e');
      return null;
    }
  }

  Future<List<ChatSession>> getSessions() async {
    if (_cache != null) {
      _sortSessions(_cache!);
      return List.from(_cache!);
    }

    final List<ChatSession> loadedSessions = [];

    if (kIsWeb) {
      for (final mdContent in _webMarkdownStore.values) {
        final s = sessionFromMarkdown(mdContent);
        if (s != null) loadedSessions.add(s);
      }
    } else {
      try {
        final dirPath = await getChatsDirectoryPath();
        final dir = Directory(dirPath);
        if (await dir.exists()) {
          final files = dir
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.md'));
          for (final file in files) {
            try {
              final content = await file.readAsString();
              final s = sessionFromMarkdown(content);
              if (s != null) {
                loadedSessions.add(s);
              }
            } catch (e) {
              debugPrint('Error reading session file ${file.path}: $e');
            }
          }
        }
      } catch (e) {
        debugPrint('Error loading chat markdown files: $e');
      }
    }

    _sortSessions(loadedSessions);
    _cache = loadedSessions;
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
    await _writeSessionToMarkdownFile(session);
  }

  Future<void> deleteSession(String id) async {
    final sessions = await getSessions();
    sessions.removeWhere((s) => s.id == id);
    _cache = sessions;

    if (kIsWeb) {
      _webMarkdownStore.remove(id);
    } else {
      try {
        final filePath = await _getSessionFilePath(id);
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        debugPrint('Error deleting chat markdown file: $e');
      }
    }
  }

  Future<void> renameSession(String id, String newTitle) async {
    final sessions = await getSessions();
    final index = sessions.indexWhere((s) => s.id == id);
    if (index >= 0) {
      sessions[index].title = newTitle;
      sessions[index].touch();
      _sortSessions(sessions);
      _cache = sessions;
      await _writeSessionToMarkdownFile(sessions[index]);
    }
  }

  Future<void> clearAllSessions() async {
    _cache = [];
    if (kIsWeb) {
      _webMarkdownStore.clear();
    } else {
      try {
        final dirPath = await getChatsDirectoryPath();
        final dir = Directory(dirPath);
        if (await dir.exists()) {
          final files = dir
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.md'));
          for (final f in files) {
            await f.delete();
          }
        }
      } catch (e) {
        debugPrint('Error clearing markdown sessions: $e');
      }
    }
  }

  Future<void> _writeSessionToMarkdownFile(ChatSession session) async {
    final md = sessionToMarkdown(session);
    if (kIsWeb) {
      _webMarkdownStore[session.id] = md;
    } else {
      try {
        final filePath = await _getSessionFilePath(session.id);
        final file = File(filePath);
        await file.writeAsString(md, flush: true);
      } catch (e) {
        debugPrint('Error writing markdown file: $e');
      }
    }
  }
}
