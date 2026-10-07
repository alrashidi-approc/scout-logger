import 'time_zone_io.dart' if (dart.library.js_interop) 'time_zone_web.dart';

/// IANA name of the browser's time zone (e.g. `Asia/Kuwait`); `UTC` when unknown.
String localTimeZone() => platformTimeZone();
