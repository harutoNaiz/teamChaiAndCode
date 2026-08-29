import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/parakeet_speech_service.dart';

/// Chat input bar with live speech-to-text feedback while recording.
/// No attachment state, no fake paths, no simulated transcripts.
class ChatInputBar extends StatefulWidget {
  /// V1: signature is text-only, no attachment params.
  final Function(String text) onSendMessage;
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
  bool _isRecording = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSendMessage(text);
    _controller.clear();
    setState(() {});
  }

  void _onMicTap() {
    if (_isRecording || ParakeetSpeechService.instance.isListening) {
      ParakeetSpeechService.instance.stopListening();
      if (mounted) setState(() => _isRecording = false);
      return;
    }
    setState(() => _isRecording = true);
    ParakeetSpeechService.instance.startListening(
      onFinalResult: (text) {
        if (!mounted) return;
        _controller.text = text;
        _controller.selection = TextSelection.collapsed(offset: text.length);
        setState(() => _isRecording = false);
      },
      onInterimResult: (text) {
        if (!mounted) return;
        // SpeechRecognizer emits interim hypotheses repeatedly. Keep the
        // latest hypothesis in the composer so the user can see words appear
        // while speaking instead of receiving one opaque result at the end.
        _controller.value = _controller.value.copyWith(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
          composing: TextRange.empty,
        );
        setState(() {});
      },
      onError: () {
        if (!mounted) return;
        setState(() => _isRecording = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Microphone permission or speech recognition is unavailable.'),
          behavior: SnackBarBehavior.floating,
        ));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasText = _controller.text.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkBg : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? AppTheme.darkBorder : const Color(0xFFEEEEEE),
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Container(
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
              const SizedBox(width: 14),

              // Text field
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
                    hintText: _isRecording
                        ? 'Listening… speak now'
                        : 'Message teamChai…',
                    hintStyle: TextStyle(
                      color:
                          isDark ? AppTheme.darkTextSecondary : Colors.black38,
                      fontSize: 15,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _handleSend(),
                ),
              ),

              // Keep the stop control visible even after interim speech text
              // appears in the composer.
              if (widget.isGenerating) ...[
                IconButton(
                  icon: const Icon(Icons.stop_circle_rounded,
                      size: 26, color: AppTheme.dangerRed),
                  onPressed: widget.onStopGenerating,
                  padding: const EdgeInsets.all(10),
                  constraints: const BoxConstraints(),
                ),
              ] else if (_isRecording) ...[
                Container(
                  margin: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.dangerRed.withValues(alpha: 0.14),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.stop_rounded,
                        size: 22, color: AppTheme.dangerRed),
                    onPressed: _onMicTap,
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(),
                    tooltip: 'Stop listening',
                  ),
                ),
              ] else if (hasText) ...[
                Container(
                  margin: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.brandAccent,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_upward_rounded,
                        size: 20, color: Colors.white),
                    onPressed: _handleSend,
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(),
                  ),
                ),
              ] else ...[
                IconButton(
                  icon: Icon(
                      ParakeetSpeechService.instance.isListening
                          ? Icons.stop_circle_outlined
                          : Icons.mic_none_rounded,
                      size: 22),
                  color: isDark ? AppTheme.darkTextSecondary : Colors.black54,
                  onPressed: _onMicTap,
                  padding: const EdgeInsets.all(12),
                  constraints: const BoxConstraints(),
                  tooltip: ParakeetSpeechService.instance.isListening
                      ? 'Stop listening'
                      : 'Use microphone',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
