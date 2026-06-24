import 'package:flutter/material.dart';

import 'clipboard_io.dart' if (dart.library.js_interop) 'clipboard_web.dart';

Future<bool> copyToClipboard(String text) => platformCopy(text);

Future<void> copyWithFeedback(
  BuildContext context,
  String text, {
  String message = 'Copied',
}) async {
  final ok = await copyToClipboard(text);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(ok ? message : 'Copy failed — select the text instead')),
  );
}
