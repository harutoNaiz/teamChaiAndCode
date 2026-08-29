import 'package:flutter/material.dart';
import '../models/file_operation_models.dart';
import '../theme/app_theme.dart';

/// V6: Read-only file-operation preview widget.
/// Flutter ONLY renders the manifest and calls back on confirm/cancel.
/// It does NOT resolve URIs, execute operations, or mutate sources.
class FileOperationPreview extends StatelessWidget {
  final PreviewManifest manifest;
  final VoidCallback onCancel;
  final ValueChanged<PreviewManifest> onConfirm;

  const FileOperationPreview({
    super.key,
    required this.manifest,
    required this.onCancel,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final opColor = _operationColor(manifest.operation);

    return Container(
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2228) : const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: opColor.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: opColor.withOpacity(0.12),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                Icon(_operationIcon(manifest.operation), size: 18, color: opColor),
                const SizedBox(width: 8),
                Text(
                  manifest.operation.label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: opColor,
                  ),
                ),
                const Spacer(),
                // Undo badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: manifest.undoAvailable
                        ? Colors.green.withOpacity(0.15)
                        : Colors.red.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    manifest.undoAvailable ? 'Undo available' : 'No undo',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color:
                          manifest.undoAvailable ? Colors.green : Colors.red,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Candidate count
                Text(
                  '${manifest.candidateCount} candidate${manifest.candidateCount == 1 ? '' : 's'}',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppTheme.darkTextPrimary : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),

                // Candidate list
                ...manifest.candidates.map((c) => _CandidateRow(
                      candidate: c,
                      isDark: isDark,
                    )),

                // Destination
                if (manifest.destination != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.drive_file_move_outline,
                          size: 14, color: AppTheme.brandAccent),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Destination: ${manifest.destination}',
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],

                // Risks
                if (manifest.risks.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: manifest.risks
                        .map((r) => _RiskChip(risk: r))
                        .toList(),
                  ),
                ],

                const SizedBox(height: 14),

                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onCancel,
                        style: OutlinedButton.styleFrom(
                          side:
                              BorderSide(color: Colors.grey.withOpacity(0.5)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('Cancel',
                            style: TextStyle(fontSize: 13)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => onConfirm(manifest),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: opColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text(
                          'Confirm ${manifest.operation.label}',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600),
                        ),
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

  Color _operationColor(FileOperation op) {
    switch (op) {
      case FileOperation.softDelete:
        return Colors.red;
      case FileOperation.move:
        return Colors.orange;
      case FileOperation.rename:
        return Colors.blue;
      case FileOperation.restore:
        return Colors.green;
      case FileOperation.list:
        return AppTheme.brandAccent;
    }
  }

  IconData _operationIcon(FileOperation op) {
    switch (op) {
      case FileOperation.softDelete:
        return Icons.delete_outline_rounded;
      case FileOperation.move:
        return Icons.drive_file_move_outline;
      case FileOperation.rename:
        return Icons.drive_file_rename_outline_rounded;
      case FileOperation.restore:
        return Icons.restore_rounded;
      case FileOperation.list:
        return Icons.list_rounded;
    }
  }
}

class _CandidateRow extends StatelessWidget {
  final CandidateFileSummary candidate;
  final bool isDark;
  const _CandidateRow({required this.candidate, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF2A2A2A)
            : Colors.white,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: isDark
              ? AppTheme.darkBorder
              : const Color(0xFFE5E7EB),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insert_drive_file_outlined,
                  size: 14, color: AppTheme.brandAccent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  candidate.displayName,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppTheme.darkTextPrimary
                        : Colors.black87,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (candidate.matchingPredicates.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Matched: ${candidate.matchingPredicates.join(', ')}',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

class _RiskChip extends StatelessWidget {
  final String risk;
  const _RiskChip({required this.risk});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.amber.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.warning_amber_rounded,
              size: 11, color: Colors.amber),
          const SizedBox(width: 4),
          Text(
            risk,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Colors.amber,
            ),
          ),
        ],
      ),
    );
  }
}
