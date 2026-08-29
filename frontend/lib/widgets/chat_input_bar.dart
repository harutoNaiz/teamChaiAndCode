import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ChatInputBar extends StatefulWidget {
  final Function(String text, String? attachmentName, String? attachmentPath) onSendMessage;
  final bool isGenerating;
  final VoidCallback? onStopGenerating;

  const ChatInputBar({
    super.key,
    required this.onSendMessage,
    this.isGenerating = false,
    this.onStopGenerating,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  String? _stagedAttachmentName;
  String? _stagedAttachmentPath;
  bool _isListeningVoice = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty && _stagedAttachmentName == null) return;

    widget.onSendMessage(
      text.isEmpty ? 'Process attached document' : text,
      _stagedAttachmentName,
      _stagedAttachmentPath,
    );

    _controller.clear();
    setState(() {
      _stagedAttachmentName = null;
      _stagedAttachmentPath = null;
      _isListeningVoice = false;
    });
  }

  void _showAttachmentSheet() {
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
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Add Context / Device Data',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.brandAccent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.picture_as_pdf_rounded, color: AppTheme.brandAccent),
                  ),
                  title: const Text('Pick PDF / Document'),
                  subtitle: const Text('Search & index local files on phone'),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _stagedAttachmentName = 'Google_SWE_Intern_2026.pdf';
                      _stagedAttachmentPath = 'Documents/Offer_Letters/Google_SWE_Intern_2026.pdf';
                    });
                  },
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.receipt_long_rounded, color: Colors.blueAccent),
                  ),
                  title: const Text('Pick Receipt / Screenshot (OCR)'),
                  subtitle: const Text('Extract tables, text & numbers via on-device OCR'),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _stagedAttachmentName = 'Swiggy_Bill_Aug28.jpg';
                      _stagedAttachmentPath = 'DCIM/Screenshots/Swiggy_Bill_Aug28.jpg';
                    });
                  },
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.purpleAccent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.camera_alt_rounded, color: Colors.purpleAccent),
                  ),
                  title: const Text('Take Camera Photo'),
                  subtitle: const Text('Instant multimodal capture and analysis'),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _stagedAttachmentName = 'Camera_Snapshot.jpg';
                      _stagedAttachmentPath = 'DCIM/Camera/IMG_20260829.jpg';
                    });
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _toggleVoiceInput() {
    setState(() => _isListeningVoice = !_isListeningVoice);
    if (_isListeningVoice) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🎙️ Listening... (Voice input activated)'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      // Simulate voice transcription after 2 seconds
      Future.delayed(const Duration(milliseconds: 1800), () {
        if (mounted && _isListeningVoice) {
          setState(() {
            _controller.text = 'Summarize my recent internship offer letter and prepare WhatsApp message';
            _isListeningVoice = false;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasText = _controller.text.trim().isNotEmpty || _stagedAttachmentName != null;

    return Container(
      padding: const EdgeInsets.only(left: 10, right: 10, bottom: 12, top: 8),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkBg : Colors.white,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [

          // Attachment staging preview if selected
          if (_stagedAttachmentName != null) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.brandAccent.withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.attachment, size: 16, color: AppTheme.brandAccent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _stagedAttachmentName!,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() {
                      _stagedAttachmentName = null;
                      _stagedAttachmentPath = null;
                    }),
                    child: const Icon(Icons.close, size: 16, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],

          // Main input capsule
          Container(
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkInputBg : const Color(0xFFF4F4F4),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: isDark ? AppTheme.darkBorder : const Color(0xFFE5E7EB),
                width: 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Plus / Attachment Button
                IconButton(
                  icon: const Icon(Icons.add_circle_outline_rounded, size: 22),
                  color: isDark ? AppTheme.darkTextSecondary : Colors.black54,
                  onPressed: _showAttachmentSheet,
                  padding: const EdgeInsets.all(12),
                  constraints: const BoxConstraints(),
                ),

                // Text Field
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    minLines: 1,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    style: TextStyle(
                      fontSize: 15,
                      color: isDark ? AppTheme.darkTextPrimary : Colors.black87,
                    ),
                    decoration: InputDecoration(
                      hintText: _isListeningVoice ? 'Listening...' : 'Message teamChai...',
                      hintStyle: TextStyle(
                        color: isDark ? AppTheme.darkTextSecondary : Colors.black38,
                        fontSize: 15,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onChanged: (val) => setState(() {}),
                    onSubmitted: (_) => _handleSend(),
                  ),
                ),

                // Voice Mic or Send Button
                if (widget.isGenerating) ...[
                  IconButton(
                    icon: const Icon(Icons.stop_circle_rounded, size: 26, color: AppTheme.dangerRed),
                    onPressed: widget.onStopGenerating,
                    padding: const EdgeInsets.all(10),
                    constraints: const BoxConstraints(),
                  ),
                ] else if (hasText) ...[
                  Container(
                    margin: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.brandAccent,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.arrow_upward_rounded, size: 20, color: Colors.white),
                      onPressed: _handleSend,
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(),
                    ),
                  ),
                ] else ...[
                  IconButton(
                    icon: Icon(
                      _isListeningVoice ? Icons.mic : Icons.mic_none_rounded,
                      size: 22,
                      color: _isListeningVoice ? AppTheme.dangerRed : (isDark ? AppTheme.darkTextSecondary : Colors.black54),
                    ),
                    onPressed: _toggleVoiceInput,
                    padding: const EdgeInsets.all(12),
                    constraints: const BoxConstraints(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
