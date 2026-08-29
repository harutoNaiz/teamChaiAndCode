import 'package:flutter/material.dart';
import '../models/retrieved_evidence.dart';
import '../theme/app_theme.dart';

/// V2: Reusable evidence card for a single RetrievedEvidence result.
/// Variants: document, image, PDF page, audio transcript, chat-memory.
class EvidenceCard extends StatefulWidget {
  final RetrievedEvidence evidence;

  /// Called with openUri when user taps "Open Source".
  /// Flutter does NOT resolve or open the URI itself.
  final ValueChanged<String>? onOpen;

  const EvidenceCard({super.key, required this.evidence, this.onOpen});

  @override
  State<EvidenceCard> createState() => _EvidenceCardState();
}

class _EvidenceCardState extends State<EvidenceCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final ev = widget.evidence;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isAvailable = ev.sourceUri.isNotEmpty && ev.openUri.isNotEmpty;

    return Container(
      width: 240,
      margin: const EdgeInsets.only(right: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF232323) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppTheme.darkBorder : const Color(0xFFE5E7EB),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header row — icon + content type badge
            Row(
              children: [
                Icon(_typeIcon(ev.contentType), size: 18, color: AppTheme.brandAccent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _typeBadge(ev),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isDark ? AppTheme.darkTextSecondary : Colors.black54,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Display name
            Text(
              ev.displayName,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? AppTheme.darkTextPrimary : Colors.black87,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 5),

            // Snippet (expandable)
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Text(
                ev.snippet.isNotEmpty ? ev.snippet : ev.transcription,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: isDark ? AppTheme.darkTextSecondary : Colors.black54,
                ),
                maxLines: _expanded ? null : 3,
                overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 6),

            // Citation ID
            Text(
              ev.identifier,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                color: Colors.grey,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),

            // Availability button
            GestureDetector(
              onTap: isAvailable
                  ? () => widget.onOpen?.call(ev.openUri)
                  : null,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isAvailable
                      ? Colors.green.withOpacity(0.12)
                      : Colors.red.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isAvailable
                        ? Colors.green.withOpacity(0.4)
                        : Colors.red.withOpacity(0.4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isAvailable ? Icons.open_in_new_rounded : Icons.block_rounded,
                      size: 11,
                      color: isAvailable ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        isAvailable ? 'Open Source' : 'Source Unavailable',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isAvailable ? Colors.green : Colors.red,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _typeIcon(String contentType) {
    switch (contentType.toLowerCase()) {
      case 'pdf_text':
      case 'pdf_ocr':
        return Icons.picture_as_pdf_rounded;
      case 'image_ocr':
        return Icons.image_rounded;
      case 'audio_transcript':
        return Icons.mic_rounded;
      case 'chat_memory':
        return Icons.chat_bubble_outline_rounded;
      default:
        return Icons.description_rounded;
    }
  }

  String _typeBadge(RetrievedEvidence ev) {
    switch (ev.contentType.toLowerCase()) {
      case 'pdf_text':
        return ev.page != null ? 'PDF page ${ev.page}' : 'PDF text';
      case 'pdf_ocr':
        return ev.page != null ? 'PDF OCR page ${ev.page}' : 'PDF OCR';
      case 'image_ocr':
        return 'Image OCR';
      case 'audio_transcript':
        return 'Audio transcript';
      case 'chat_memory':
        return 'Chat memory';
      default:
        return 'Document';
    }
  }
}
