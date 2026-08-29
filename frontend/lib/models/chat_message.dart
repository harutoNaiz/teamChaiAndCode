import 'agent_action.dart';
import 'file_operation_models.dart';
import '../widgets/grounded_state_banner.dart';

enum MessageRole { user, assistant, system }

class ChatMessage {
  final String id;
  final MessageRole role;
  String content;
  final DateTime timestamp;
  final List<AgentAction> actions;
  bool isStreaming;
  String? thoughtProcess;

  /// Citation IDs referencing RetrievedEvidence.identifier values
  final List<String> citationIds;

  /// Grounded state for this message (null = normal)
  GroundedState? groundedState;

  /// Cloud model name when cloudPrivacyNotice state is set
  String? cloudModelName;

  /// File-operation preview manifest (V6)
  PreviewManifest? previewManifest;

  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    List<AgentAction>? actions,
    this.isStreaming = false,
    this.thoughtProcess,
    List<String>? citationIds,
    this.groundedState,
    this.cloudModelName,
    this.previewManifest,
  })  : actions = actions ?? [],
        citationIds = citationIds ?? [];

  bool get isUser => role == MessageRole.user;
  bool get isAssistant => role == MessageRole.assistant;

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role.name,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
        'actions': actions.map((a) => a.toJson()).toList(),
        'thoughtProcess': thoughtProcess,
        'citationIds': citationIds,
        'groundedState': groundedState?.name,
        'cloudModelName': cloudModelName,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final gsRaw = json['groundedState'] as String?;
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
      citationIds: (json['citationIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      groundedState: gsRaw == null
          ? null
          : GroundedState.values.firstWhere(
              (e) => e.name == gsRaw,
              orElse: () => GroundedState.noResults,
            ),
      cloudModelName: json['cloudModelName'] as String?,
    );
  }
}
