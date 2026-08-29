import 'chat_message.dart';

class ChatSession {
  final String id;
  String title;
  final DateTime createdAt;
  DateTime updatedAt;
  List<ChatMessage> messages;
  String? compressedSummary;
  String selectedModelId;

  ChatSession({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    List<ChatMessage>? messages,
    this.compressedSummary,
    this.selectedModelId = 'gemini-1.5-flash',
  }) : messages = messages ?? [];

  void touch() {
    updatedAt = DateTime.now();
  }

  void addMessage(ChatMessage message) {
    messages.add(message);
    touch();
    if (messages.length == 1 && title == 'New Chat' && message.isUser) {
      // Auto-title from first user message
      final words = message.content.trim().split(RegExp(r'\s+'));
      title = words.take(6).join(' ');
      if (title.isEmpty) title = 'New Conversation';
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'messages': messages.map((m) => m.toJson()).toList(),
        'compressedSummary': compressedSummary,
        'selectedModelId': selectedModelId,
      };

  factory ChatSession.fromJson(Map<String, dynamic> json) {
    return ChatSession(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'New Chat',
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt'] ?? '') ?? DateTime.now(),
      messages: (json['messages'] as List<dynamic>?)
              ?.map((m) => ChatMessage.fromJson(Map<String, dynamic>.from(m)))
              .toList() ??
          [],
      compressedSummary: json['compressedSummary'] as String?,
      selectedModelId: json['selectedModelId'] as String? ?? 'gemini-1.5-flash',
    );
  }
}
