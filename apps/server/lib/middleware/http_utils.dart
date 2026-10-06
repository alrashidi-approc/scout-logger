import 'dart:convert';
import 'dart:io' hide BytesBuilder;
import 'dart:typed_data';

import 'package:shelf/shelf.dart';

import '../config/server_config.dart';

/// `/v1/*` (ingest, client config, shares) is called from any app origin; everything else only from [ServerConfig.corsOrigins].
Middleware corsMiddleware(ServerConfig config) => (Handler inner) {
      return (Request request) async {
        final origin = request.headers['origin'];
        final allow = request.url.path.startsWith('v1/')
            ? '*'
            : config.corsOrigins.contains(origin)
                ? origin
                : null;
        final headers = {
          if (allow != null) 'Access-Control-Allow-Origin': allow,
          if (allow != null && allow != '*') 'Vary': 'Origin',
          'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
          'Access-Control-Allow-Headers': 'Origin, Content-Type, Accept, Authorization, X-API-Key',
        };
        if (request.method == 'OPTIONS') return Response.ok('', headers: headers);
        final response = await inner(request);
        return response.change(headers: headers);
      };
    };

bool constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}

Response jsonOk(Object body, {int status = 200}) => Response(
      status,
      body: body is String ? body : null,
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );

Response jsonErr(String message, {int status = 400}) =>
    Response(status, body: jsonEncode({'ok': false, 'error': message}), headers: {'Content-Type': 'application/json'});

const maxBodyBytes = 10 * 1024 * 1024;

class BodyTooLargeException implements Exception {
  @override
  String toString() => 'Request body exceeds $maxBodyBytes bytes';
}

/// Throws [BodyTooLargeException] past [maxBodyBytes] without buffering the rest of the stream.
Future<String> readBody(Request request) async {
  if ((request.contentLength ?? 0) > maxBodyBytes) throw BodyTooLargeException();
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in request.read()) {
    if (bytes.length + chunk.length > maxBodyBytes) throw BodyTooLargeException();
    bytes.add(chunk);
  }
  return utf8.decode(bytes.takeBytes());
}

String? bearerToken(Request request) {
  final auth = request.headers['authorization'] ?? request.headers['Authorization'];
  if (auth == null || !auth.toLowerCase().startsWith('bearer ')) return null;
  return auth.substring(7).trim();
}

String? remoteIp(Request request) {
  final info = request.context['shelf.io.connection_info'];
  if (info is HttpConnectionInfo) return info.remoteAddress.address;
  return null;
}

Map<String, String> headerMap(Request request) =>
    request.headers.map((k, v) => MapEntry(k.toLowerCase(), v));
