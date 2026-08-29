import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/chat_message.dart';
import '../models/retrieved_evidence.dart';
import '../models/file_operation_models.dart';
import '../theme/app_theme.dart';
import 'grounded_state_banner.dart';
import 'evidence_list.dart';
import 'file_operation_preview.dart';
import 'permission_action_card.dart';

/// V1+V3+V5+V6: Chat message bubble.
/// - V1: No attachment chip display
/// - V3: Shows GroundedStateBanner when groundedState is set
/// - V5: Shows EvidenceList for cited evidence matched by citationIds
/// - V6: Shows FileOperationPreview when previewManifest is set
class ChatMessageBubble extends StatefulWidget {
  final ChatMessage message;
  final VoidCallback? onActionUpdated;

  /// V5: Available evidence for citation matching
  final List<RetrievedEvidence>? availableEvidence;
  final ValueChanged<String>? onOpenSource;

  /// V6: Callbacks for file-operation preview
  final ValueChanged<PreviewManifest>? onConfirmOperation;
  final VoidCallback? onCancelOperation;

  const ChatMessageBubble({
    super.key,
    required this.message,
    this.onActionUpdated,
    this.availableEvidence,
    this.onOpenSource,
    this.onConfirmOperation,
    this.onCancelOperation,
  });

  @override
  State<ChatMessageBubble> createState() => _ChatMessageBubbleState();
}

class _ChatMessageBubbleState extends State<ChatMessageBubble> {
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
              // V1: No attachment chip — plain text only
              child: SelectableText(
                msg.content,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.4,
                  color: isDark ? AppTheme.darkTextPrimary : Colors.black87,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssistantBubble(BuildContext context, bool isDark) {
    final msg = widget.message;

    // V5: Match cited evidence by identifier
    final citedEvidence = <RetrievedEvidence>[];
    if (widget.availableEvidence != null && msg.citationIds.isNotEmpty) {
      for (final id in msg.citationIds) {
        final match =
            widget.availableEvidence!.where((e) => e.identifier == id).toList();
        citedEvidence.addAll(match);
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      color: Colors.transparent,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Assistant avatar
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

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // V3: Grounded state banner
                if (msg.groundedState != null)
                  GroundedStateBanner(
                    state: msg.groundedState!,
                    cloudModelName: msg.cloudModelName,
                  ),

                // Reasoning metadata is retained internally but never shown
                // in the user-facing response.

                // Main content
                SelectableText(
                  msg.content,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.45,
                    color: isDark ? AppTheme.darkTextPrimary : Colors.black87,
                  ),
                ),

                // V5: Citation evidence cards
                if (citedEvidence.isNotEmpty)
                  EvidenceList(
                    evidences: citedEvidence,
                    onOpen: widget.onOpenSource,
                  ),

                // V6: File-operation preview
                if (msg.previewManifest != null)
                  FileOperationPreview(
                    manifest: msg.previewManifest!,
                    onCancel: widget.onCancelOperation ?? () {},
                    onConfirm: widget.onConfirmOperation ?? (_) {},
                  ),

                // Tool action cards
                if (msg.actions.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  ...msg.actions.map((act) => PermissionActionCard(
                        action: act,
                        onStateChanged: widget.onActionUpdated,
                      )),
                ],

                // Action bar
                const SizedBox(height: 6),
                Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.copy_rounded,
                          size: 15,
                          color: isDark
                              ? AppTheme.darkTextSecondary
                              : Colors.black45),
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
