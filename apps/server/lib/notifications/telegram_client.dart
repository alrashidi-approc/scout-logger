import 'dart:convert';
import 'dart:io';

/// Telegram Bot API. [postJson] is injected in tests.
class TelegramClient {
  TelegramClient(this.token, {this.postJson});

  final String token;
  final Future<int> Function(Uri uri, Map<String, dynamic> body)? postJson;

  Future<int> sendMessage({
    required String chatId,
    required String text,
    Map<String, dynamic>? replyMarkup,
  }) {
    return _post('sendMessage', {
      'chat_id': chatId,
      'text': text,
      'disable_web_page_preview': true,
      if (replyMarkup != null) 'reply_markup': replyMarkup,
    });
  }

  Future<void> answerCallbackQuery(String callbackId, {String? text}) async {
    await _post('answerCallbackQuery', {
      'callback_query_id': callbackId,
      if (text != null && text.isNotEmpty) 'text': _clipCallback(text),
      'show_alert': false,
    });
  }

  String _clipCallback(String text) => text.length <= 180 ? text : '${text.substring(0, 180)}…';

  Future<void> setMyCommands() async {
    final status = await _post('setMyCommands', {
      'commands': [
        {'command': 'health', 'description': 'Latest server health check'},
        {'command': 'up', 'description': 'Live uptime'},
        {'command': 'stats', 'description': 'Last 24 hours'},
        {'command': 'release', 'description': 'Issues since the latest release'},
        {'command': 'issues', 'description': 'Top open issues'},
        {'command': 'report', 'description': 'Admin report as text'},
        {'command': 'pause', 'description': 'Silence alerts for 1 hour'},
        {'command': 'help', 'description': 'What this bot can do'},
      ],
    });
    if (status < 200 || status >= 300) {
      throw Exception('Telegram setMyCommands HTTP $status');
    }
  }

  Future<void> setWebhook({required String url, required String secret}) async {
    final status = await _post('setWebhook', {
      'url': url,
      'secret_token': secret,
      'allowed_updates': ['message', 'callback_query'],
    });
    if (status < 200 || status >= 300) {
      throw Exception('Telegram setWebhook HTTP $status');
    }
  }

  Future<int> _post(String method, Map<String, dynamic> body) async {
    final uri = Uri.parse('https://api.telegram.org/bot$token/$method');
    final send = postJson;
    if (send != null) return send(uri, body);

    final client = HttpClient();
    try {
      final req = await client.postUrl(uri);
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
      final res = await req.close();
      final raw = await res.transform(utf8.decoder).join();
      if (res.statusCode >= 400) return res.statusCode;
      final decoded = raw.isEmpty ? null : jsonDecode(raw);
      if (decoded is Map && decoded['ok'] == false) {
        final code = decoded['error_code'];
        if (code is int && code >= 400) return code;
        return 400;
      }
      return res.statusCode;
    } finally {
      client.close(force: true);
    }
  }
}
