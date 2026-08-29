import 'agent_action.dart';

enum MessageRole {
  user,
  assistant,
  system,
}

class ChatMessage {
  final String id;
  final MessageRole role;
  String content;
  final DateTime timestamp;
  final List<AgentAction> actions;
  bool isStreaming;
  String? thoughtProcess;
  String? attachmentPath;
  String? attachmentName;

  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    List<AgentAction>? actions,
    this.isStreaming = false,
    this.thoughtProcess,
    this.attachmentPath,
    this.attachmentName,
  }) : actions = actions ?? [];

  bool get isUser => role == MessageRole.user;
  bool get isAssistant => role == MessageRole.assistant;

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role.name,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
        'actions': actions.map((a) => a.toJson()).toList(),
        'thoughtProcess': thoughtProcess,
        'attachmentPath': attachmentPath,
        'attachmentName': attachmentName,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      role: MessageRole.values.firstWhere(
        (e) => e.name == json['role'],
        orElse: () => MessageRole.user,
      ),
      content: json['content'] as String? ?? '',
      timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
      actions: (json['actions'] as List<dynamic>?)
              ?.map((a) => AgentAction.fromJson(Map<String, dynamic>.from(a)))
              .toList() ??
          [],
      thoughtProcess: json['thoughtProcess'] as String?,
      attachmentPath: json['attachmentPath'] as String?,
      attachmentName: json['attachmentName'] as String?,
    );
  }
}
