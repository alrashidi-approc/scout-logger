import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../services/api_client.dart';

/// Returns chosen expiry in days, or null if cancelled.
Future<int?> pickShareExpiry(BuildContext context) => showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Share link'),
        content: const Text(
          'Anyone with this URL can view this item until the link expires. No login or project access is granted.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 1), child: const Text('1 day')),
          TextButton(onPressed: () => Navigator.pop(ctx, 7), child: const Text('1 week')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 30), child: const Text('1 month')),
        ],
      ),
    );

Future<void> copyShareLink(
  BuildContext context, {
  required String projectId,
  required String type,
  required String resourceId,
}) async {
  final days = await pickShareExpiry(context);
  if (days == null || !context.mounted) return;

  try {
    final res = await ScoutApi().createShareLink(
      projectId,
      type: type,
      resourceId: resourceId,
      expiresInDays: days,
    );
    await Clipboard.setData(ClipboardData(text: res['url'] as String));
    if (!context.mounted) return;

    final expiresAt = DateTime.tryParse(res['expiresAt'] as String? ?? '');
    final expiryLabel = expiresAt != null ? DateFormat.yMMMd().add_jm().format(expiresAt.toLocal()) : '$days days';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Share link copied · expires $expiryLabel')),
    );
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
  }
}
