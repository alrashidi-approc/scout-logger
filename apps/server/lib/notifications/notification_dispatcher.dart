import 'dart:convert';
import 'dart:io';

import 'package:mailer/mailer.dart' as mailer;
import 'package:mailer/smtp_server.dart';
import 'package:scout_models/scout_models.dart';

import '../services/key_cipher.dart';
import 'notification_router.dart';

class NotificationDispatcher {
  NotificationDispatcher({KeyCipher? cipher}) : _cipher = cipher;

  final KeyCipher? _cipher;

  Future<void> send({
    required NotificationJob job,
    required ProjectNotificationConfig config,
    required String projectName,
  }) async {
    switch (job.channel) {
      case 'slack':
        await _sendSlack(job, config);
      case 'whatsapp':
        await _sendWhatsapp(job, config);
      case 'email':
        await _sendEmail(job, config, projectName);
      default:
        throw UnsupportedError('Unknown channel ${job.channel}');
    }
  }

  String? _decrypt(String? enc) => _cipher?.decrypt(enc) ?? enc;

  Future<void> _sendSlack(NotificationJob job, ProjectNotificationConfig config) async {
    final url = _decrypt(config.slack.webhookUrlEnc);
    if (url == null || url.isEmpty) throw StateError('Slack webhook not configured');

    final client = HttpClient();
    try {
      final req = await client.postUrl(Uri.parse(url));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({
        'text': '*${job.title}*\n${job.body}\n<${job.eventUrl}|Open in Scout>',
      }));
      final res = await req.close();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw HttpException('Slack HTTP ${res.statusCode}', uri: Uri.parse(url));
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _sendWhatsapp(NotificationJob job, ProjectNotificationConfig config) async {
    final phone = _decrypt(config.whatsapp.phoneEnc);
    final apiKey = _decrypt(config.whatsapp.apiKeyEnc);
    if (phone == null || apiKey == null) throw StateError('WhatsApp not configured');

    final text = '${job.title}\n\n${job.body}\n\n${job.eventUrl}';
    final uri = Uri.https('api.callmebot.com', '/whatsapp.php', {
      'phone': phone,
      'text': text,
      'apikey': apiKey,
    });

    final client = HttpClient();
    try {
      final req = await client.getUrl(uri);
      final res = await req.close();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw HttpException('CallMeBot HTTP ${res.statusCode}', uri: uri);
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _sendEmail(NotificationJob job, ProjectNotificationConfig config, String projectName) async {
    final user = _decrypt(config.email.smtpUserEnc);
    final pass = _decrypt(config.email.smtpPasswordEnc);
    final from = _decrypt(config.email.fromEnc) ?? user;
    if (user == null || pass == null || from == null) throw StateError('Email SMTP not configured');
    if (config.email.recipients.isEmpty) throw StateError('No email recipients');

    final server = SmtpServer(
      config.email.smtpHost,
      port: config.email.smtpPort,
      username: user,
      password: pass,
      ssl: config.email.smtpPort == 465,
      allowInsecure: false,
    );

    final message = mailer.Message()
      ..from = mailer.Address(from, 'Scout Logger')
      ..recipients.addAll(config.email.recipients)
      ..subject = '[Scout] $projectName — ${job.title}'
      ..text = '${job.body}\n\nOpen: ${job.eventUrl}';

    await mailer.send(message, server);
  }
}
