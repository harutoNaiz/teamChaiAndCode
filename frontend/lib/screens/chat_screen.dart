import 'package:flutter/material.dart';
import '../models/chat_session.dart';
import '../models/chat_message.dart';
import '../models/ai_model_config.dart';
import '../services/chat_storage_service.dart';
import '../services/agent_service.dart';
import '../theme/app_theme.dart';
import '../widgets/chat_drawer.dart';
import '../widgets/chat_message_bubble.dart';
import '../widgets/chat_input_bar.dart';
import '../widgets/model_selector_sheet.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scrollController = ScrollController();

  ChatSession? _currentSession;
  AIModelConfig _currentModel = AIModelConfig.availableModels.first;
  bool _isGenerating = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeChat();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initializeChat() async {
    final sessions = await ChatStorageService.instance.getSessions();
    final savedModelId = await AgentService.instance.getSavedSelectedModelId();

    if (mounted) {
      setState(() {
        if (savedModelId != null) {
          _currentModel = AIModelConfig.availableModels.firstWhere(
            (m) => m.id == savedModelId,
            orElse: () => AIModelConfig.availableModels.first,
          );
        }

        if (sessions.isNotEmpty && sessions.first.messages.isEmpty) {
          // Reuse a blank draft rather than creating duplicates on cold start.
          _currentSession = sessions.first;
        } else if (sessions.isNotEmpty) {
          // Exactly one fresh draft is created when the previous latest chat
          // contains messages. Subsequent rebuilds do not enter this path.
          _currentSession = ChatSession(
            id: 'session-${DateTime.now().millisecondsSinceEpoch}',
            title: 'New Chat',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            selectedModelId: _currentModel.id,
          );
          ChatStorageService.instance.saveSession(_currentSession!);
          _scrollToBottom();
        } else {
          _currentSession = ChatSession(
            id: 'session-${DateTime.now().millisecondsSinceEpoch}',
            title: 'New Chat',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            selectedModelId: _currentModel.id,
          );
          ChatStorageService.instance.saveSession(_currentSession!);
          if (savedModelId == null) {
            _currentModel = AIModelConfig.availableModels.firstWhere(
              (m) => m.id == _currentSession!.selectedModelId,
              orElse: () => _currentModel,
            );
          }
        }
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  void _createNewChat() {
    final newSession = ChatSession(
      id: 'session-${DateTime.now().millisecondsSinceEpoch}',
      title: 'New Chat',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      selectedModelId: _currentModel.id,
    );

    setState(() {
      _currentSession = newSession;
    });

    ChatStorageService.instance.saveSession(newSession);
    _scrollToBottom();
  }

  void _selectSession(ChatSession session) {
    setState(() {
      _currentSession = session;
      _currentModel = AIModelConfig.availableModels.firstWhere(
        (m) => m.id == session.selectedModelId,
        orElse: () => _currentModel,
      );
    });
    _scrollToBottom();
  }

  void _selectModel(AIModelConfig model) {
    setState(() {
      _currentModel = model;
      if (_currentSession != null) {
        _currentSession!.selectedModelId = model.id;
        ChatStorageService.instance.saveSession(_currentSession!);
      }
    });
    AgentService.instance.saveSelectedModel(model.id);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _handleSendMessage(String text) async {
    if (_currentSession == null || _isGenerating) return;

    final userMessage = ChatMessage(
      id: 'msg-user-${DateTime.now().millisecondsSinceEpoch}',
      role: MessageRole.user,
      content: text,
      timestamp: DateTime.now(),
    );

    setState(() {
      _currentSession!.addMessage(userMessage);
      _isGenerating = true;
    });
    _scrollToBottom();

    // Persist immediately
    await ChatStorageService.instance.saveSession(_currentSession!);

    try {
      final responseMessage = await AgentService.instance.sendMessage(
        session: _currentSession!,
        prompt: text,
        modelConfig: _currentModel,
      );

      if (mounted) {
        setState(() {
          _currentSession!.addMessage(responseMessage);
          _isGenerating = false;
        });
        await ChatStorageService.instance.saveSession(_currentSession!);
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        final errorMessage = ChatMessage(
          id: 'msg-err-${DateTime.now().millisecondsSinceEpoch}',
          role: MessageRole.assistant,
          content:
              '⚠️ An error occurred while communicating with the agent: $e',
          timestamp: DateTime.now(),
        );
        setState(() {
          _currentSession!.addMessage(errorMessage);
          _isGenerating = false;
        });
        await ChatStorageService.instance.saveSession(_currentSession!);
        _scrollToBottom();
      }
    }
  }

  void _showModelSelectorSheet() {
    ModelSelectorSheet.show(
      context,
      currentModel: _currentModel,
      onSelectModel: _selectModel,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading) {
      return const Scaffold(
        body: Center(
            child: CircularProgressIndicator(color: AppTheme.brandAccent)),
      );
    }

    final messages = _currentSession?.messages ?? [];

    return Scaffold(
      key: _scaffoldKey,
      drawer: ChatDrawer(
        activeSessionId: _currentSession?.id ?? '',
        onSelectSession: _selectSession,
        onNewChat: _createNewChat,
        onSelectModel: _selectModel,
        currentModel: _currentModel,
      ),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded, size: 22),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: InkWell(
          onTap: _showModelSelectorSheet,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFEBEBEB),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _currentModel.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppTheme.darkTextPrimary : Colors.black87,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 16,
                  color: isDark ? AppTheme.darkTextSecondary : Colors.black54,
                ),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_square, size: 20),
            tooltip: 'New Chat',
            onPressed: _createNewChat,
          ),
        ],
      ),
      body: Column(
        children: [
          // Main Chat Area or Empty Welcome State
          Expanded(
            child: messages.isEmpty
                ? _buildEmptyState(context, isDark)
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    itemCount: messages.length + (_isGenerating ? 1 : 0),
                    itemBuilder: (ctx, idx) {
                      if (idx < messages.length) {
                        return ChatMessageBubble(
                          message: messages[idx],
                          onActionUpdated: () {
                            ChatStorageService.instance
                                .saveSession(_currentSession!);
                            setState(() {});
                          },
                        );
                      } else {
                        // Animated Thinking / Typing Indicator
                        return _buildThinkingIndicator(isDark);
                      }
                    },
                  ),
          ),

          // Bottom Input Bar
          ChatInputBar(
            onSendMessage: _handleSendMessage,
            isGenerating: _isGenerating,
            onStopGenerating: () => setState(() => _isGenerating = false),
          ),
        ],
      ),
    );
  }

  Widget _buildThinkingIndicator(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.brandAccent, Color(0xFF0D8C6C)],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Center(
              child: Icon(Icons.auto_awesome, size: 16, color: Colors.white),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkCard : const Color(0xFFE9ECEF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppTheme.brandAccent),
                ),
                const SizedBox(width: 10),
                Text(
                  'Reasoning & executing tools...',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? AppTheme.darkTextSecondary : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF1F3F5),
              shape: BoxShape.circle,
              border: Border.all(
                  color: AppTheme.brandAccent.withOpacity(0.4), width: 1.5),
            ),
            child: const Center(
              child: Icon(Icons.auto_awesome,
                  size: 26, color: AppTheme.brandAccent),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'What can I do for you today?',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: isDark ? AppTheme.darkTextPrimary : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}
