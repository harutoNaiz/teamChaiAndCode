// V4: Session indexing state enum
enum SessionIndexingState { notIndexed, indexing, indexed, failed }

class ChatSession {
  final String id;
  String title;
  final DateTime createdAt;
  DateTime updatedAt;
  String selectedModelId;
  String? compressedSummary;
  final List<dynamic> messages; // ChatMessage — kept dynamic to avoid circular
  SessionIndexingState indexingState;

  ChatSession({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.selectedModelId,
    this.compressedSummary,
    List<dynamic>? messages,
    this.indexingState = SessionIndexingState.notIndexed,
  }) : messages = messages ?? [];

  void touch() {
    updatedAt = DateTime.now();
  }

  void addMessage(dynamic message) {
    messages.add(message);
    touch();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'selectedModelId': selectedModelId,
        'compressedSummary': compressedSummary,
        'indexingState': indexingState.name,
        'messages': messages.map((m) => m.toJson()).toList(),
      };

  factory ChatSession.fromJson(Map<String, dynamic> json) {
    final rawState = json['indexingState'] as String?;
    return ChatSession(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Chat',
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt'] ?? '') ?? DateTime.now(),
      selectedModelId: json['selectedModelId'] as String? ?? '',
      compressedSummary: json['compressedSummary'] as String?,
      indexingState: rawState == null
          ? SessionIndexingState.notIndexed
          : SessionIndexingState.values.firstWhere(
              (e) => e.name == rawState,
              orElse: () => SessionIndexingState.notIndexed,
            ),
    );
  }
}
