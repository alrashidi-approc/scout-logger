import 'download_file_io.dart' if (dart.library.js_interop) 'download_file_web.dart';

/// Saves [content] as a browser download. Returns false where downloads aren't supported.
Future<bool> downloadTextFile(String filename, String content, {String mimeType = 'text/plain'}) =>
    platformDownload(filename, content, mimeType);
