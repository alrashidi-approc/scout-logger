import 'dart:io';

import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

import '../config/server_config.dart';

class EmailService {
  EmailService(this.config);

  final ServerConfig config;

  bool get enabled => config.smtpHost.isNotEmpty;

  Future<String?> sendVerification({required String to, required String token}) async {
    final link = '${config.publicUrl}${config.dashboardUrlPath}/verify-email?token=$token';
    final subject = 'Verify your Scout Logger account';
    final body = '''
Hello,

Verify your email to start using Scout Logger:

$link

This link expires in 24 hours.

— Scout Logger
''';
    return _send(to: to, subject: subject, body: body, devLabel: 'verification link');
  }

  Future<String?> _send({
    required String to,
    required String subject,
    required String body,
    required String devLabel,
  }) async {
    if (!enabled) {
      stdout.writeln('[scout-email] SMTP not configured — $devLabel for $to');
      stdout.writeln(body.trim());
      return linkFromBody(body);
    }
    final server = SmtpServer(
      config.smtpHost,
      port: config.smtpPort,
      username: config.smtpUser.isEmpty ? null : config.smtpUser,
      password: config.smtpPassword.isEmpty ? null : config.smtpPassword,
      ssl: config.smtpPort == 465,
      allowInsecure: config.smtpAllowInsecure,
    );
    await send(
      Message()
        ..from = Address(config.smtpFrom, 'Scout Logger')
        ..recipients.add(to)
        ..subject = subject
        ..text = body,
      server,
    );
    return null;
  }

  String? linkFromBody(String body) {
    final match = RegExp(r'https?://[^\s]+').firstMatch(body);
    return match?.group(0);
  }
}
