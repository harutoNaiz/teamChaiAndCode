import 'package:flutter/material.dart';
import '../models/agent_action.dart';
import '../services/agent_service.dart';
import '../theme/app_theme.dart';

class PermissionActionCard extends StatefulWidget {
  final AgentAction action;
  final VoidCallback? onStateChanged;

  const PermissionActionCard({
    super.key,
    required this.action,
    this.onStateChanged,
  });

  @override
  State<PermissionActionCard> createState() => _PermissionActionCardState();
}

class _PermissionActionCardState extends State<PermissionActionCard> {
  bool _isLoading = false;

  IconData _getActionIcon(String type) {
    switch (type) {
      case 'send_whatsapp':
        return Icons.chat_bubble_outline_rounded;
      case 'search_files':
        return Icons.folder_open_rounded;
      case 'ocr_image':
        return Icons.document_scanner_rounded;
      case 'organize_files':
        return Icons.drive_file_move_outline;
      case 'delete_file':
        return Icons.delete_outline_rounded;
      default:
        return Icons.smart_toy_outlined;
    }
  }

  Color _getRiskColor(ActionPermissionLevel level) {
    switch (level) {
      case ActionPermissionLevel.safe:
        return AppTheme.brandAccent;
      case ActionPermissionLevel.medium:
        return AppTheme.warningOrange;
      case ActionPermissionLevel.sensitive:
        return AppTheme.dangerRed;
    }
  }

  String _getRiskLabel(ActionPermissionLevel level) {
    switch (level) {
      case ActionPermissionLevel.safe:
        return 'Safe • Auto';
      case ActionPermissionLevel.medium:
        return 'Moderate Risk';
      case ActionPermissionLevel.sensitive:
        return 'Requires Permission';
    }
  }

  Future<void> _handleApprove() async {
    setState(() => _isLoading = true);
    await AgentService.instance.executeAction(widget.action);
    if (mounted) {
      setState(() => _isLoading = false);
      widget.onStateChanged?.call();
    }
  }

  void _handleDecline() {
    setState(() {
      widget.action.status = ActionStatus.declined;
    });
    widget.onStateChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final action = widget.action;
    final riskColor = _getRiskColor(action.permissionLevel);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(top: 10, bottom: 4),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkElevated : const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: action.requiresConfirmation
              ? riskColor.withOpacity(0.38)
              : (isDark ? AppTheme.hairline : const Color(0xFFE5E7EB)),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.20 : 0.04),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: riskColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(_getActionIcon(action.type),
                    size: 18, color: riskColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  action.title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: riskColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _getRiskLabel(action.permissionLevel),
                  style: TextStyle(
                      color: riskColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Description
          Text(
            action.description,
            style: TextStyle(
              fontSize: 13,
              color:
                  isDark ? AppTheme.darkTextSecondary : const Color(0xFF4B5563),
              height: 1.3,
            ),
          ),

          // Action Parameters preview if available
          if (action.parameters.isNotEmpty && action.requiresConfirmation) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkInset : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: isDark
                        ? AppTheme.hairline
                        : const Color(0xFFEEF0F2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: action.parameters.entries.map((e) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      '${e.key}: ${e.value}',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11.5,
                        color: isDark
                            ? AppTheme.darkTextSecondary
                            : Colors.black87,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],

          // Footer / Status / Buttons
          const SizedBox(height: 12),
          if (action.requiresConfirmation) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: _isLoading ? null : _handleDecline,
                  style: OutlinedButton.styleFrom(
                    foregroundColor:
                        isDark ? AppTheme.darkTextSecondary : Colors.black54,
                    side: BorderSide(
                        color: isDark
                            ? AppTheme.darkBorder
                            : const Color(0xFFD1D5DB)),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    minimumSize: Size.zero,
                  ),
                  child:
                      const Text('Decline', style: TextStyle(fontSize: 12.5)),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _handleApprove,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.brandAccent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    minimumSize: Size.zero,
                  ),
                  icon: _isLoading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check, size: 15),
                  label: Text(_isLoading ? 'Executing...' : 'Approve & Run',
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ] else ...[
            Row(
              children: [
                Icon(
                  action.status == ActionStatus.completed
                      ? Icons.check_circle_rounded
                      : (action.status == ActionStatus.declined
                          ? Icons.cancel_rounded
                          : Icons.pending_outlined),
                  size: 14,
                  color: action.status == ActionStatus.completed
                      ? AppTheme.brandAccent
                      : (action.status == ActionStatus.declined
                          ? AppTheme.dangerRed
                          : Colors.grey),
                ),
                const SizedBox(width: 5),
                Text(
                  action.status == ActionStatus.completed
                      ? 'Action successfully executed'
                      : (action.status == ActionStatus.declined
                          ? 'Action declined by user'
                          : 'Processing...'),
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isDark
                        ? AppTheme.darkTextSecondary
                        : const Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
