import 'telegram_commands.dart';

final _startCommand = RegExp(r'^/start(?:@\w+)?(?:\s+(\S+))?$');

/// Payload of `/start <token>` or `/start@Bot <token>`. Null when it is not a connect command.
String? telegramStartPayload(String text) {
  final match = _startCommand.firstMatch(text.trim());
  if (match == null) return null;
  final token = match.group(1)?.trim();
  if (token == null || token.isEmpty) return null;
  return token;
}

String telegramChatTitle(Map<String, dynamic> chat) {
  final title = chat['title']?.toString().trim();
  String raw;
  if (title != null && title.isNotEmpty) {
    raw = title;
  } else {
    final name = '${chat['first_name'] ?? ''} ${chat['last_name'] ?? ''}'.trim();
    final username = chat['username']?.toString().trim();
    raw = name.isNotEmpty
        ? name
        : (username != null && username.isNotEmpty ? '@$username' : 'Telegram chat');
  }
  final cleaned = raw.replaceAll(RegExp(r'[\r\n\t]'), ' ').trim();
  if (cleaned.length <= 120) return cleaned;
  return cleaned.substring(0, 120);
}

/// Reply text for a bot update, or null when the update should be ignored.
/// Group chatter is ignored. Private text that is not a command gets the menu.
Future<String?> handleTelegramUpdate({
  required Map<String, dynamic> update,
  required Future<String?> Function(String token) consumeLink,
  required Future<void> Function(String projectId, String chatId, String chatTitle) bind,
  required Future<String?> Function(String projectId) projectName,
  Future<String?> Function(String chatId)? projectForChat,
  Future<String> Function(String projectId, String command)? runCommand,
}) async {
  final message = update['message'];
  if (message is! Map) return null;
  final chat = message['chat'];
  if (chat is! Map) return null;
  final chatMap = Map<String, dynamic>.from(chat);
  if (chatMap['type']?.toString() == 'channel') return null;
  final chatId = chatMap['id']?.toString();
  if (chatId == null || chatId.isEmpty) return null;

  final text = message['text']?.toString() ?? '';
  final token = telegramStartPayload(text);
  if (token != null) {
    final projectId = await consumeLink(token);
    if (projectId == null) {
      return 'This connect link has expired or was already used. Create a new one in Scout.';
    }
    await bind(projectId, chatId, telegramChatTitle(chatMap));
    final name = (await projectName(projectId))?.trim();
    final label = (name == null || name.isEmpty) ? projectId : name;
    return 'Connected to $label. Alerts for this project will arrive here.\n\n$telegramCommandHelp';
  }

  final command = telegramCommand(text);
  final private = chatMap['type']?.toString() == 'private';
  if (command == null) return private && text.trim().isNotEmpty ? telegramOnlyThese() : null;
  if (command == 'unknown') return telegramOnlyThese();

  final lookup = projectForChat;
  final run = runCommand;
  if (lookup == null || run == null) return telegramNotConnected();
  final projectId = await lookup(chatId);
  if (projectId == null) return telegramNotConnected();
  return run(projectId, command);
}
