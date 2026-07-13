import 'dart:convert';
import 'dart:io';

import 'package:mailer/mailer.dart' as mailer;
import 'package:mailer/smtp_server.dart';
import 'package:scout_models/scout_models.dart';

import '../services/key_cipher.dart';
import 'notification_router.dart';

class NotificationDispatcher {
  NotificationDispatcher({
    KeyCipher? cipher,
    this.maxAttempts = 3,
    this.baseDelay = const Duration(seconds: 2),
    this.slackInteractive = false,
  }) : _cipher = cipher;

  final KeyCipher? _cipher;

  /// When true, Slack messages include Resolve/Mute action buttons.
  final bool slackInteractive;

  /// Total attempts per job (1 initial + retries). Config errors aren't retried.
  final int maxAttempts;
  final Duration baseDelay;

  Future<void> send({
    required NotificationJob job,
    required ProjectNotificationConfig config,
    required String projectName,
  }) async {
    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        await _dispatch(job: job, config: config, projectName: projectName);
        return;
      } on _PermanentSendError {
        rethrow;
      } catch (e) {
        lastError = e;
        if (attempt < maxAttempts) await Future.delayed(baseDelay * attempt);
      }
    }
    throw Exception(_describeFailure(lastError));
  }

  /// DNS/connection failures are server-side network problems, not bad creds —
  /// give a clear hint so users don't keep regenerating app passwords.
  String _describeFailure(Object? e) {
    final s = '$e';
    final lower = s.toLowerCase();
    if (e is SocketException ||
        lower.contains('failed host lookup') ||
        lower.contains('temporary failure in name resolution') ||
        lower.contains('errno = 3') ||
        lower.contains('connection refused') ||
        lower.contains('network is unreachable')) {
      return 'Network/DNS error: the Scout server could not resolve or reach the host. '
          'This is a server-side networking issue (not your password). Check the server\'s '
          'DNS (/etc/resolv.conf or container --dns) and that outbound SMTP ports 587/465 are open. ($s)';
    }
    return 'Failed after $maxAttempts attempts: $s';
  }

  Future<void> _dispatch({
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
        throw _PermanentSendError('Unknown channel ${job.channel}');
    }
  }

  String? _decrypt(String? enc) => _cipher?.decrypt(enc) ?? enc;

  Future<void> _sendSlack(
      NotificationJob job, ProjectNotificationConfig config) async {
    final url = _decrypt(config.slack.webhookUrlEnc);
    if (url == null || url.isEmpty)
      throw _PermanentSendError('Slack webhook not configured');

    final text = '*${job.title}*\n${job.body}\n<${job.eventUrl}|Open in Scout>';
    final payload = <String, dynamic>{'text': text};
    if (slackInteractive && job.issueId != null) {
      payload['blocks'] = [
        {
          'type': 'section',
          'text': {'type': 'mrkdwn', 'text': text},
        },
        {
          'type': 'actions',
          'elements': [
            {
              'type': 'button',
              'text': {'type': 'plain_text', 'text': '✅ Resolve'},
              'action_id': 'resolve_issue',
              'value': '${job.issueId}',
            },
            {
              'type': 'button',
              'text': {'type': 'plain_text', 'text': '🔕 Mute'},
              'action_id': 'mute_issue',
              'value': '${job.issueId}',
            },
          ],
        },
      ];
    }

    final client = HttpClient();
    try {
      final req = await client.postUrl(Uri.parse(url));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(payload));
      final res = await req.close();
      await res.drain();
      _checkHttp('Slack', res.statusCode);
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _sendWhatsapp(
      NotificationJob job, ProjectNotificationConfig config) async {
    final phone = _decrypt(config.whatsapp.phoneEnc);
    final apiKey = _decrypt(config.whatsapp.apiKeyEnc);
    if (phone == null || apiKey == null)
      throw _PermanentSendError('WhatsApp not configured');

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
      await res.drain();
      _checkHttp('CallMeBot', res.statusCode);
    } finally {
      client.close(force: true);
    }
  }

  /// 4xx is a permanent config error (bad token/URL); 5xx and network errors retry.
  void _checkHttp(String channel, int status) {
    if (status >= 200 && status < 300) return;
    if (status >= 400 && status < 500)
      throw _PermanentSendError('$channel HTTP $status');
    throw Exception('$channel HTTP $status');
  }

  Future<void> _sendEmail(NotificationJob job, ProjectNotificationConfig config,
      String projectName) async {
    final user = _decrypt(config.email.smtpUserEnc);
    final pass = _decrypt(config.email.smtpPasswordEnc);
    final from = _decrypt(config.email.fromEnc) ?? user;
    if (user == null || pass == null || from == null)
      throw _PermanentSendError('Email SMTP not configured');
    if (config.email.recipients.isEmpty)
      throw _PermanentSendError('No email recipients');

    // The server's OS resolver may be broken (errno -3). Resolve ourselves and
    // connect by IP when needed, so a missing /etc/resolv.conf can't block mail.
    var host = config.email.smtpHost;
    var ignoreBadCertificate = false;
    try {
      await InternetAddress.lookup(host);
    } on SocketException {
      final ip = await _resolveViaDoH(host);
      if (ip == null) {
        throw _PermanentSendError(
            'Could not resolve $host: the server has no working DNS and the DNS-over-HTTPS fallback also failed. Fix the server\'s DNS or outbound HTTPS.');
      }
      host = ip;
      // Cert won't match a bare IP; the channel stays TLS-encrypted, but the IP
      // came from a validated HTTPS resolver so this is an acceptable fallback.
      ignoreBadCertificate = true;
    }

    // final server = SmtpServer(
    //   host,
    //   port: config.email.smtpPort,
    //   username: user,
    //   password: pass,
    //   ssl: config.email.smtpPort == 465,
    //   allowInsecure: false,
    //   ignoreBadCertificate: ignoreBadCertificate,
    // );
    final server = gmail(user, pass);

    final message = mailer.Message()
      ..from = mailer.Address(from, 'Scout Logger')
      ..recipients.addAll(config.email.recipients)
      ..subject = _emailSubject(projectName: projectName, job: job)
      ..text = '${job.body}\n\nOpen: ${job.eventUrl}';

    try {
      await mailer.send(message, server);
    } on mailer.MailerException catch (e) {
      // SMTP auth/sender problems won't fix themselves on retry.
      final detail = e.problems.isNotEmpty
          ? e.problems.map((p) => p.msg).join('; ')
          : e.message;
      final lower = detail.toLowerCase();
      if (lower.contains('username and password not accepted') ||
          lower.contains('authentication') ||
          lower.contains('5.7.') ||
          lower.contains('535')) {
        throw _PermanentSendError(
            'Gmail rejected the login. Use a Google App Password (16 chars, 2-step verification on), not your normal password. ($detail)');
      }
      if (lower.contains('5.7.0') ||
          lower.contains('does not match') ||
          lower.contains('sender')) {
        throw _PermanentSendError(
            'Gmail rejected the sender. The "From" must be the same Gmail address you authenticate with. ($detail)');
      }
      throw _PermanentSendError('Email send failed: $detail');
    }
  }
}

String _emailSubject({required String projectName, required NotificationJob job}) {
  final env = job.environment?.trim();
  final envPart = env != null && env.isNotEmpty ? ' [$env]' : '';
  return '[Scout]$envPart $projectName — ${job.title}';
}

/// Resolve [host] to an A-record IP via DNS-over-HTTPS, bypassing the OS
/// resolver. The resolver endpoints are literal IPs (no DNS needed) and their
/// TLS certs include those IPs, so the lookup itself stays validated.
Future<String?> _resolveViaDoH(String host) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    for (final resolver in const ['1.1.1.1', '8.8.8.8']) {
      try {
        final req = await client.getUrl(
            Uri.https(resolver, '/dns-query', {'name': host, 'type': 'A'}));
        req.headers.set(HttpHeaders.acceptHeader, 'application/dns-json');
        final res = await req.close();
        if (res.statusCode != 200) {
          await res.drain();
          continue;
        }
        final json = jsonDecode(await res.transform(utf8.decoder).join());
        final answers = json is Map ? json['Answer'] : null;
        if (answers is List) {
          for (final a in answers) {
            if (a is Map && a['type'] == 1 && a['data'] is String)
              return a['data'] as String;
          }
        }
      } catch (_) {
        // Try the next resolver.
      }
    }
    return null;
  } finally {
    client.close(force: true);
  }
}

/// Config/auth failures that won't succeed on retry (missing creds, HTTP 4xx).
class _PermanentSendError implements Exception {
  _PermanentSendError(this.message);
  final String message;
  @override
  String toString() => message;
}
