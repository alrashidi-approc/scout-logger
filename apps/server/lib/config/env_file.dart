import 'dart:io';

/// Loads key=value pairs from the project root `.env` file.
class EnvFile {
  EnvFile(this.values);

  final Map<String, String> values;

  String? operator [](String key) => values[key] ?? Platform.environment[key];

  static EnvFile load({String? path}) {
    final file = path != null ? File(path) : _findDotEnv();
    if (file == null || !file.existsSync()) {
      return EnvFile({...Platform.environment});
    }
    final parsed = _parse(file.readAsStringSync());
    return EnvFile({...Platform.environment, ...parsed});
  }

  static File? _findDotEnv() {
    var dir = Directory.current;
    while (true) {
      final candidate = File('${dir.path}/.env');
      if (candidate.existsSync()) return candidate;
      final parent = dir.parent;
      if (parent.path == dir.path) return null;
      dir = parent;
    }
  }

  static Map<String, String> _parse(String content) {
    final out = <String, String>{};
    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final eq = trimmed.indexOf('=');
      if (eq <= 0) continue;
      final key = trimmed.substring(0, eq).trim();
      var value = trimmed.substring(eq + 1).trim();
      if ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'"))) {
        value = value.substring(1, value.length - 1);
      }
      out[key] = value;
    }
    return out;
  }
}

/// Repo root (directory that contains `.env`), if found from [Directory.current].
String? projectRootFromEnv() {
  var dir = Directory.current;
  while (true) {
    if (File('${dir.path}/.env').existsSync()) return dir.path;
    final parent = dir.parent;
    if (parent.path == dir.path) return null;
    dir = parent;
  }
}
