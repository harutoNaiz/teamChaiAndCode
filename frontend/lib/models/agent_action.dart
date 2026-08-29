enum ActionPermissionLevel {
  safe, // Auto-executed, no user prompt needed (e.g. read files, search)
  medium, // Low impact with undo option (e.g. move/rename notes)
  sensitive, // High impact, explicit approval needed (e.g. send message, delete file, financial)
}

enum ActionStatus {
  pendingApproval,
  approved,
  declined,
  executing,
  completed,
  failed,
}

class AgentAction {
  final String id;
  final String type;
  final String title;
  final String description;
  final ActionPermissionLevel permissionLevel;
  ActionStatus status;
  final Map<String, dynamic> parameters;
  Map<String, dynamic>? result;
  String? errorMessage;

  AgentAction({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.permissionLevel,
    this.status = ActionStatus.pendingApproval,
    required this.parameters,
    this.result,
    this.errorMessage,
  });

  bool get requiresConfirmation =>
      permissionLevel == ActionPermissionLevel.sensitive &&
      status == ActionStatus.pendingApproval;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'title': title,
        'description': description,
        'permissionLevel': permissionLevel.name,
        'status': status.name,
        'parameters': parameters,
        'result': result,
        'errorMessage': errorMessage,
      };

  factory AgentAction.fromJson(Map<String, dynamic> json) {
    return AgentAction(
      id: json['id'] as String,
      type: json['type'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      permissionLevel: ActionPermissionLevel.values.firstWhere(
        (e) => e.name == json['permissionLevel'],
        orElse: () => ActionPermissionLevel.safe,
      ),
      status: ActionStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => ActionStatus.completed,
      ),
      parameters: Map<String, dynamic>.from(json['parameters'] ?? {}),
      result: json['result'] != null
          ? Map<String, dynamic>.from(json['result'])
          : null,
      errorMessage: json['errorMessage'] as String?,
    );
  }
}
