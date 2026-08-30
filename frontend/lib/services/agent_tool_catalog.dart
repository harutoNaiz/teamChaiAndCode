import '../models/agent_action.dart';

/// Tool definitions exposed to the intent/planning model. Execution remains
/// behind typed platform contracts and permission gates.
class AgentToolDefinition {
  final String name;
  final String description;
  final ActionPermissionLevel permission;
  final Map<String, String> parameters;

  const AgentToolDefinition(
      this.name, this.description, this.permission, this.parameters);

  Map<String, dynamic> toPromptJson() => {
        'name': name,
        'description': description,
        'permission': permission.name,
        'parameters': parameters,
      };
}

class AgentToolCatalog {
  static const definitions = <AgentToolDefinition>[
    AgentToolDefinition(
        'search_files',
        'Search indexed files, OCR, transcripts and chat memory',
        ActionPermissionLevel.safe,
        {'query': 'string'}),
    AgentToolDefinition(
        'list_files',
        'List authorised files using metadata, path and name filters',
        ActionPermissionLevel.safe,
        {'filter': 'object'}),
    AgentToolDefinition(
        'ocr_image',
        'Run OCR on an authorised image or PDF page',
        ActionPermissionLevel.safe,
        {'source_uri': 'string'}),
    AgentToolDefinition(
        'create_reminder',
        'Create a device reminder after confirmation of time and text',
        ActionPermissionLevel.medium,
        {'title': 'string', 'at': 'ISO-8601 datetime'}),
    AgentToolDefinition(
        'create_note',
        "Save a note to the phone's notes app (Keep/Samsung Notes/etc.) after confirmation",
        ActionPermissionLevel.medium,
        {'title': 'string', 'content': 'string'}),
    AgentToolDefinition(
        'move_file',
        'Move an authorised file into a destination folder, created if absent',
        ActionPermissionLevel.medium,
        {'source_id': 'file name', 'destination': 'folder name'}),
    AgentToolDefinition(
        'rename_file',
        'Rename an authorised file',
        ActionPermissionLevel.medium,
        {'source_id': 'string', 'new_name': 'string'}),
    AgentToolDefinition(
        'soft_delete_file',
        'Delete an authorised file after confirmation',
        ActionPermissionLevel.sensitive,
        {'source_id': 'string'}),
    AgentToolDefinition(
        'restore_file',
        'Restore an item from the app trash manifest',
        ActionPermissionLevel.medium,
        {'source_id': 'string'}),
    AgentToolDefinition(
        'organize_downloads',
        'Group Downloads using a previewed move plan',
        ActionPermissionLevel.medium,
        {'rules': 'object'}),
    AgentToolDefinition(
        'upsert_file',
        'Create or update an indexed file/catalog record',
        ActionPermissionLevel.medium,
        {'uri': 'string', 'content': 'string'}),
    AgentToolDefinition(
        'send_whatsapp',
        'Prepare a WhatsApp message for explicit user approval',
        ActionPermissionLevel.sensitive,
        {'contact': 'string', 'message': 'string'}),
  ];

  static String asPrompt() => definitions
      .map((definition) => definition.toPromptJson().toString())
      .join('\n');

  static AgentToolDefinition? byName(String name) {
    for (final definition in definitions) {
      if (definition.name == name) return definition;
    }
    return null;
  }
}
