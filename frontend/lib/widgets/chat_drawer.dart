import 'package:flutter/material.dart';
import '../models/chat_session.dart';
import '../models/ai_model_config.dart';
import '../services/chat_storage_service.dart';
import '../services/scanner_service.dart';
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
        final matchMessages =
            s.messages.any((m) => m.content.toLowerCase().contains(q));
        return matchTitle || matchMessages;
      }).toList();
    }
  }

  Map<String, List<ChatSession>> _groupSessionsByDate(
      List<ChatSession> sessions) {
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
                await ChatStorageService.instance
                    .renameSession(session.id, newTitle);
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
            style:
                ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerRed),
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

  /// V4: Small icon showing session indexing state.
  Widget _buildIndexingStateIcon(SessionIndexingState state) {
    switch (state) {
      case SessionIndexingState.notIndexed:
        return const SizedBox.shrink();
      case SessionIndexingState.indexing:
        return const SizedBox(
          width: 10,
          height: 10,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: AppTheme.brandAccent,
          ),
        );
      case SessionIndexingState.indexed:
        return const Icon(Icons.check_circle, size: 12, color: Colors.green);
      case SessionIndexingState.failed:
        return const Icon(Icons.error, size: 12, color: AppTheme.dangerRed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final grouped = _groupSessionsByDate(_filteredSessions);

    return Drawer(
      backgroundColor: isDark ? AppTheme.darkSurface : const Color(0xFFF9F9F9),
      child: SafeArea(
        child: Column(
          children: [
            // Top section: chat search. New chat is available in the AppBar.
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: Column(
                children: [
                  Container(
                    height: 42,
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF262626)
                          : const Color(0xFFEBEBEB),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: TextField(
                      controller: _searchController,
                      style: TextStyle(
                        fontSize: 14,
                        color:
                            isDark ? AppTheme.darkTextPrimary : Colors.black87,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search chats...',
                        hintStyle: TextStyle(
                          color: isDark
                              ? AppTheme.darkTextSecondary
                              : Colors.black45,
                          fontSize: 14,
                        ),
                        prefixIcon: Icon(
                          Icons.search,
                          size: 18,
                          color: isDark
                              ? AppTheme.darkTextSecondary
                              : Colors.black45,
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
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onChanged: (val) => setState(() => _filterSessions(val)),
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
                              color: isDark
                                  ? AppTheme.darkTextSecondary
                                  : Colors.black45,
                              fontSize: 13,
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          itemCount: grouped.length,
                          itemBuilder: (ctx, idx) {
                            final groupTitle = grouped.keys.elementAt(idx);
                            final sessionsInGroup = grouped[groupTitle]!;

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(10, 14, 10, 6),
                                  child: Text(
                                    groupTitle,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? AppTheme.darkTextSecondary
                                          : const Color(0xFF6B7280),
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ),
                                ...sessionsInGroup.map((session) {
                                  final isActive =
                                      session.id == widget.activeSessionId;

                                  return InkWell(
                                    onTap: () {
                                      Navigator.pop(context);
                                      widget.onSelectSession(session);
                                    },
                                    onLongPress: () =>
                                        _showRenameDialog(session),
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(
                                          vertical: 2),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 9),
                                      decoration: BoxDecoration(
                                        color: isActive
                                            ? (isDark
                                                ? const Color(0xFF333333)
                                                : const Color(0xFFE5E7EB))
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
                                                : (isDark
                                                    ? AppTheme.darkTextSecondary
                                                    : Colors.black54),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              session.title,
                                              style: TextStyle(
                                                fontSize: 13.5,
                                                fontWeight: isActive
                                                    ? FontWeight.w600
                                                    : FontWeight.normal,
                                                color: isDark
                                                    ? AppTheme.darkTextPrimary
                                                    : Colors.black87,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          // V4: Session indexing state icon
                                          _buildIndexingStateIcon(
                                              session.indexingState),
                                          const SizedBox(width: 2),
                                          PopupMenuButton<String>(
                                            icon: Icon(
                                              Icons.more_horiz,
                                              size: 16,
                                              color: isDark
                                                  ? AppTheme.darkTextSecondary
                                                  : Colors.black45,
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
                                                    Icon(Icons.edit_outlined,
                                                        size: 16),
                                                    SizedBox(width: 8),
                                                    Text('Rename'),
                                                  ],
                                                ),
                                              ),
                                              const PopupMenuItem(
                                                value: 'delete',
                                                child: Row(
                                                  children: [
                                                    Icon(Icons.delete_outline,
                                                        color:
                                                            AppTheme.dangerRed,
                                                        size: 16),
                                                    SizedBox(width: 8),
                                                    Text('Delete',
                                                        style: TextStyle(
                                                            color: AppTheme
                                                                .dangerRed)),
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
                  // Local Scanner / OCR Ingestion Tile
                  InkWell(
                    onTap: () async {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Opening folder picker...')),
                      );
                      // Import dynamic call to scanner service
                      final result =
                          await ScannerService.instance.pickAndScanFolder();
                      if (context.mounted) {
                        if (result.isSuccess) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  'Indexed ${result.records.length} document(s) & photo(s) from selected folder.'),
                              backgroundColor: AppTheme.brandAccent,
                            ),
                          );
                        } else if (result.status == 'error') {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Scan error: ${result.error}'),
                              backgroundColor: AppTheme.dangerRed,
                            ),
                          );
                        }
                      }
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 4, horizontal: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.document_scanner_outlined,
                              size: 16, color: AppTheme.brandAccent),
                          const SizedBox(width: 8),
                          Text(
                            'Scan Folder / Photos (OCR)',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? AppTheme.darkTextPrimary
                                  : Colors.black87,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const Spacer(),
                          const Icon(Icons.folder_open,
                              size: 16, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Refresh: burst-index new/changed files, skip already-seen.
                  InkWell(
                    onTap: () async {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content:
                                Text('Refreshing index - scanning for new files...')),
                      );
                      final result =
                          await ScannerService.instance.refreshIndex();
                      if (context.mounted) {
                        if (result.isSuccess) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  'Indexed ${result.indexedCount} new item(s). Catalog: ${result.catalogRecordCount} record(s).'),
                              backgroundColor: AppTheme.brandAccent,
                            ),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Refresh failed: ${result.error}'),
                              backgroundColor: AppTheme.dangerRed,
                            ),
                          );
                        }
                      }
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 4, horizontal: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.refresh_rounded,
                              size: 16, color: AppTheme.brandAccent),
                          const SizedBox(width: 8),
                          Text(
                            'Refresh Index (new files)',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? AppTheme.darkTextPrimary
                                  : Colors.black87,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const Spacer(),
                          const Icon(Icons.sync,
                              size: 16, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
