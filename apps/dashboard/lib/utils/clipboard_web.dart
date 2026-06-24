import 'dart:js_interop';

import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

Future<bool> platformCopy(String text) async {
  try {
    await web.window.navigator.clipboard.writeText(text).toDart;
    return true;
  } catch (_) {}

  try {
    await Clipboard.setData(ClipboardData(text: text));
    return true;
  } catch (_) {}

  return _execCommandCopy(text);
}

bool _execCommandCopy(String text) {
  final ta = web.HTMLTextAreaElement()
    ..value = text
    ..style.position = 'fixed'
    ..style.left = '-9999px';
  web.document.body?.append(ta);
  ta.select();
  final ok = web.document.execCommand('copy');
  ta.remove();
  return ok;
}
