import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<bool> platformDownload(String filename, String content, String mimeType) async {
  final blob = web.Blob([content.toJS].toJS, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);
  web.HTMLAnchorElement()
    ..href = url
    ..download = filename
    ..click();
  Future.delayed(const Duration(seconds: 1), () => web.URL.revokeObjectURL(url));
  return true;
}
