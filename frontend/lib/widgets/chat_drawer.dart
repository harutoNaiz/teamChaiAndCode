import 'package:flutter/material.dart';
import '../models/chat_session.dart';
import '../models/ai_model_config.dart';
import '../services/chat_storage_service.dart';
import '../services/agent_service.dart';
import '../theme/app_theme.dart';

class ChatDrawer extends StatefulWidget {
  final String activeSessionId;
  final Function(ChatSession session) onSelectSession;
  final VoidCallback onNewChat;
  final Function(AIModelConfig model) onSelectModel;
  final AIModelConfig currentModel;

  const ChatDrawer({
    super.key,
    required this.activeSessionId,
    required this.onSelectSession,
    required this.onNewChat,
    required this.onSelectModel,
    required this.currentModel,
  });

  @override
  State<ChatDrawer> createState() => _ChatDrawerState();
}

class _ChatDrawerState extends State<ChatDrawer> {
  final TextEditingController _searchController = TextEditingController();
  List<ChatSession> _allSessions = [];
  List<ChatSession> _filteredSessions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    final sessions = await ChatStorageService.instance.getSessions();
    if (mounted) {
      setState(() {
        _allSessions = sessions;
        _filterSessions(_searchController.text);
        _isLoading = false;
      });
    }
  }

  void _filterSessions(String query) {
    if (query.trim().isEmpty) {
      _filteredSessions = List.from(_allSessions);
    } else {
      final q = query.toLowerCase();
      _filteredSessions = _allSessions.where((s) {
        final matchTitle = s.title.toLowerCase().contains(q);
        final matchMessages = s.messages.any((m) => m.content.toLowerCase().contains(q));
        return matchTitle || matchMessages;
      }).toList();
    }
  }

  Map<String, List<ChatSession>> _groupSessionsByDate(List<ChatSession> sessions) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final sevenDaysAgo = today.subtract(const Duration(days: 7));
    final thirtyDaysAgo = today.subtract(const Duration(days: 30));

    final Map<String, List<ChatSession>> groups = {
      'Today': [],
      'Yesterday': [],
      'Previous 7 Days': [],
      'Previous 30 Days': [],
      'Older': [],
    };

    for (final s in sessions) {
      final updated = s.updatedAt;
      final sessionDate = DateTime(updated.year, updated.month, updated.day);

      if (sessionDate.isAtSameMomentAs(today) || sessionDate.isAfter(today)) {
        groups['Today']!.add(s);
      } else if (sessionDate.isAtSameMomentAs(yesterday)) {
        groups['Yesterday']!.add(s);
      } else if (sessionDate.isAfter(sevenDaysAgo)) {
        groups['Previous 7 Days']!.add(s);
      } else if (sessionDate.isAfter(thirtyDaysAgo)) {
        groups['Previous 30 Days']!.add(s);
      } else {
        groups['Older']!.add(s);
      }
    }

    groups.removeWhere((key, value) => value.isEmpty);
    return groups;
  }

  void _showRenameDialog(ChatSession session) {
    final controller = TextEditingController(text: session.title);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Chat'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Enter chat title'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newTitle = controller.text.trim();
              if (newTitle.isNotEmpty) {
                await ChatStorageService.instance.renameSession(session.id, newTitle);
                await _loadSessions();
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(ChatSession session) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Chat'),
        content: Text('Are you sure you want to delete "${session.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerRed),
            onPressed: () async {
              await ChatStorageService.instance.deleteSession(session.id);
              await _loadSessions();
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showApiKeyDialog() {
    final controller = TextEditingController(text: AgentService.instance.openRouterApiKey);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('OpenRouter API Key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter your OpenRouter key to connect DeepSeek, Llama 3.3, Claude 3.5, or Gemini directly:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              obscureText: true,
              decoration: const InputDecoration(
                hintText: 'sk-or-v1-...',
                prefixIcon: Icon(Icons.vpn_key_outlined, size: 18),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              await AgentService.instance.setOpenRouterApiKey(controller.text);
              setState(() {});
              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('OpenRouter API Key saved!')),
                );
              }
            },
            child: const Text('Save Key'),
          ),
        ],
      ),
    );
  }

  void _showModelSelectionModal() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Select OpenRouter / AI Engine',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                ...AIModelConfig.availableModels.map((model) {
                  final isSelected = model.id == widget.currentModel.id;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isSelected ? AppTheme.brandAccent.withOpacity(0.15) : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        model.isLocal ? Icons.memory_rounded : Icons.cloud_outlined,
                        color: isSelected ? AppTheme.brandAccent : Colors.grey,
                      ),
                    ),
                    title: Row(
                      children: [
                        Text(model.name, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: model.isLocal ? Colors.purple.withOpacity(0.15) : Colors.blue.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            model.badge,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: model.isLocal ? Colors.purpleAccent : Colors.blueAccent,
                            ),
                          ),
                        ),
                      ],
                    ),
                    subtitle: Text(model.description, style: const TextStyle(fontSize: 12)),
                    trailing: isSelected ? const Icon(Icons.check_circle, color: AppTheme.brandAccent, size: 20) : null,
                    onTap: () {
                      widget.onSelectModel(model);
                      Navigator.pop(ctx);
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final grouped = _groupSessionsByDate(_filteredSessions);
    final hasApiKey = AgentService.instance.openRouterApiKey.isNotEmpty;

    return Drawer(
      backgroundColor: isDark ? AppTheme.darkSurface : const Color(0xFFF9F9F9),
      child: SafeArea(
        child: Column(
          children: [
            // Top Section: Search Bar & New Chat Button
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: Column(
                children: [
                  Container(
                    height: 42,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF262626) : const Color(0xFFEBEBEB),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: TextField(
                      controller: _searchController,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? AppTheme.darkTextPrimary : Colors.black87,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search chats...',
                        hintStyle: TextStyle(
                          color: isDark ? AppTheme.darkTextSecondary : Colors.black45,
                          fontSize: 14,
                        ),
                        prefixIcon: Icon(
                          Icons.search,
                          size: 18,
                          color: isDark ? AppTheme.darkTextSecondary : Colors.black45,
                        ),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? GestureDetector(
                                onTap: () {
                                  _searchController.clear();
                                  setState(() => _filterSessions(''));
                                },
                                child: const Icon(Icons.clear, size: 16),
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onChanged: (val) => setState(() => _filterSessions(val)),
                    ),
                  ),
                  const SizedBox(height: 10),

                  InkWell(
                    onTap: () {
                      Navigator.pop(context);
                      widget.onNewChat();
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF2F2F2F) : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isDark ? AppTheme.darkBorder : const Color(0xFFE5E7EB),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.add_rounded, size: 20, color: AppTheme.brandAccent),
                          const SizedBox(width: 10),
                          Text(
                            'New Chat',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isDark ? AppTheme.darkTextPrimary : Colors.black87,
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            Icons.edit_square,
                            size: 16,
                            color: isDark ? AppTheme.darkTextSecondary : Colors.black45,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const Divider(height: 1, thickness: 0.5),

            // Middle Section: Time-Grouped Chat Sessions
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredSessions.isEmpty
                      ? Center(
                          child: Text(
                            'No conversations yet',
                            style: TextStyle(
                              color: isDark ? AppTheme.darkTextSecondary : Colors.black45,
                              fontSize: 13,
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          itemCount: grouped.length,
                          itemBuilder: (ctx, idx) {
                            final groupTitle = grouped.keys.elementAt(idx);
                            final sessionsInGroup = grouped[groupTitle]!;

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(10, 14, 10, 6),
                                  child: Text(
                                    groupTitle,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: isDark ? AppTheme.darkTextSecondary : const Color(0xFF6B7280),
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ),
                                ...sessionsInGroup.map((session) {
                                  final isActive = session.id == widget.activeSessionId;

                                  return InkWell(
                                    onTap: () {
                                      Navigator.pop(context);
                                      widget.onSelectSession(session);
                                    },
                                    onLongPress: () => _showRenameDialog(session),
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(vertical: 2),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                                      decoration: BoxDecoration(
                                        color: isActive
                                            ? (isDark ? const Color(0xFF333333) : const Color(0xFFE5E7EB))
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.chat_bubble_outline_rounded,
                                            size: 16,
                                            color: isActive
                                                ? AppTheme.brandAccent
                                                : (isDark ? AppTheme.darkTextSecondary : Colors.black54),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              session.title,
                                              style: TextStyle(
                                                fontSize: 13.5,
                                                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                                                color: isDark ? AppTheme.darkTextPrimary : Colors.black87,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          PopupMenuButton<String>(
                                            icon: Icon(
                                              Icons.more_horiz,
                                              size: 16,
                                              color: isDark ? AppTheme.darkTextSecondary : Colors.black45,
                                            ),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                            onSelected: (val) {
                                              if (val == 'rename') {
                                                _showRenameDialog(session);
                                              } else if (val == 'delete') {
                                                _showDeleteDialog(session);
                                              }
                                            },
                                            itemBuilder: (ctx) => [
                                              const PopupMenuItem(
                                                value: 'rename',
                                                child: Row(
                                                  children: [
                                                    Icon(Icons.edit_outlined, size: 16),
                                                    SizedBox(width: 8),
                                                    Text('Rename'),
                                                  ],
                                                ),
                                              ),
                                              const PopupMenuItem(
                                                value: 'delete',
                                                child: Row(
                                                  children: [
                                                    Icon(Icons.delete_outline, color: AppTheme.dangerRed, size: 16),
                                                    SizedBox(width: 8),
                                                    Text('Delete', style: TextStyle(color: AppTheme.dangerRed)),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }),
                              ],
                            );
                          },
                        ),
            ),

            const Divider(height: 1, thickness: 0.5),

            // Bottom Profile & Configuration Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              color: isDark ? const Color(0xFF1B1B1B) : const Color(0xFFF1F3F5),
              child: Column(
                children: [
                  // Model Selector Tile
                  InkWell(
                    onTap: _showModelSelectionModal,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppTheme.brandAccent.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Icon(
                              widget.currentModel.isLocal ? Icons.memory : Icons.auto_awesome,
                              size: 16,
                              color: AppTheme.brandAccent,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.currentModel.name,
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  widget.currentModel.badge,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark ? AppTheme.darkTextSecondary : Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.unfold_more_rounded, size: 18, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),

                  // OpenRouter API Key Setting
                  InkWell(
                    onTap: _showApiKeyDialog,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                      child: Row(
                        children: [
                          Icon(Icons.key_rounded, size: 16, color: hasApiKey ? AppTheme.brandAccent : Colors.grey),
                          const SizedBox(width: 8),
                          Text(
                            hasApiKey ? 'OpenRouter Key (Active)' : 'Set OpenRouter Key',
                            style: TextStyle(
                              fontSize: 12,
                              color: hasApiKey ? AppTheme.brandAccent : (isDark ? AppTheme.darkTextSecondary : Colors.black54),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const Spacer(),
                          const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
