import 'package:flutter/services.dart';

Future<bool> platformCopy(String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  return true;
}
