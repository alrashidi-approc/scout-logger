import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';

class KeyCipher {
  KeyCipher(String secret)
      : _encrypter = Encrypter(AES(Key(Uint8List.fromList(sha256.convert(utf8.encode(secret)).bytes))));

  final Encrypter _encrypter;

  String encrypt(String plain) {
    final iv = IV.fromSecureRandom(16);
    return '${iv.base64}:${_encrypter.encrypt(plain, iv: iv).base64}';
  }

  String? decrypt(String? stored) {
    if (stored == null || stored.isEmpty) return null;
    final i = stored.indexOf(':');
    if (i <= 0) return null;
    try {
      return _encrypter.decrypt(
        Encrypted.fromBase64(stored.substring(i + 1)),
        iv: IV.fromBase64(stored.substring(0, i)),
      );
    } catch (_) {
      return null;
    }
  }
}

String hashToken(String token) => sha256.convert(utf8.encode(token)).toString();

String newToken() {
  final r = Random.secure();
  final bytes = List<int>.generate(32, (_) => r.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
