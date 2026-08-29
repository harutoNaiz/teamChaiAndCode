import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/chat_message.dart';
import '../theme/app_theme.dart';
import 'permission_action_card.dart';

class ChatMessageBubble extends StatefulWidget {
  final ChatMessage message;
  final VoidCallback? onActionUpdated;

  const ChatMessageBubble({
    super.key,
    required this.message,
    this.onActionUpdated,
  });

  @override
  State<ChatMessageBubble> createState() => _ChatMessageBubbleState();
}

class _ChatMessageBubbleState extends State<ChatMessageBubble> {
  bool _showThoughts = false;

  void _copyToClipboard(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard'),
        duration: Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final msg = widget.message;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (msg.isUser) {
      return _buildUserBubble(context, isDark);
    } else {
      return _buildAssistantBubble(context, isDark);
    }
  }

  Widget _buildUserBubble(BuildContext context, bool isDark) {
    final msg = widget.message;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color:
                    isDark ? AppTheme.userBubbleDark : const Color(0xFFE9ECEF),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(4),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (msg.attachmentName != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.black26 : Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.attach_file,
                              size: 14, color: AppTheme.brandAccent),
                          const SizedBox(width: 4),
                          Text(
                            msg.attachmentName!,
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ],
                  SelectableText(
                    msg.content,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.4,
                      color: isDark ? AppTheme.darkTextPrimary : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssistantBubble(BuildContext context, bool isDark) {
    final msg = widget.message;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      color: Colors.transparent,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Assistant Icon / Avatar
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.brandAccent, Color(0xFF0D8C6C)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Center(
              child: Icon(Icons.auto_awesome, size: 17, color: Colors.white),
            ),
          ),
          const SizedBox(width: 12),

          // Message Content Body
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Thought Process Accordion (if available)
                if (msg.thoughtProcess != null &&
                    msg.thoughtProcess!.isNotEmpty) ...[
                  GestureDetector(
                    onTap: () => setState(() => _showThoughts = !_showThoughts),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF2A2A2A)
                            : const Color(0xFFF1F3F5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.psychology_outlined,
                            size: 14,
                            color: isDark
                                ? AppTheme.darkTextSecondary
                                : Colors.black54,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _showThoughts
                                ? 'Hide Reasoning'
                                : 'View Agent Reasoning',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? AppTheme.darkTextSecondary
                                  : Colors.black54,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            _showThoughts
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            size: 14,
                            color: isDark
                                ? AppTheme.darkTextSecondary
                                : Colors.black54,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_showThoughts)
                    Container(
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1E1E1E)
                            : const Color(0xFFE9ECEF),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: isDark
                                ? AppTheme.darkBorder
                                : const Color(0xFFD1D5DB)),
                      ),
                      child: SelectableText(
                        msg.thoughtProcess!,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11.5,
                          height: 1.35,
                          color: isDark
                              ? AppTheme.darkTextSecondary
                              : Colors.black87,
                        ),
                      ),
                    ),
                ],

                // Main Assistant Markdown Text
                SelectableText(
                  msg.content,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.45,
                    color: isDark ? AppTheme.darkTextPrimary : Colors.black87,
                  ),
                ),

                // Tool Actions / Permission Cards
                if (msg.actions.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  ...msg.actions.map((act) => PermissionActionCard(
                        action: act,
                        onStateChanged: widget.onActionUpdated,
                      )),
                ],

                // Action Bar below message (Copy, etc.)
                const SizedBox(height: 6),
                Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.copy_rounded,
                        size: 15,
                        color: isDark
                            ? AppTheme.darkTextSecondary
                            : Colors.black45,
                      ),
                      tooltip: 'Copy text',
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 4),
                      onPressed: () => _copyToClipboard(context, msg.content),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatTime(msg.timestamp),
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? AppTheme.darkTextSecondary
                            : Colors.black45,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final hour =
        time.hour > 12 ? time.hour - 12 : (time.hour == 0 ? 12 : time.hour);
    final minute = time.minute.toString().padLeft(2, '0');
    final ampm = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $ampm';
  }
}
