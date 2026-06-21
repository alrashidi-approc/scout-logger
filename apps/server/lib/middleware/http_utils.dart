import 'dart:io';

import 'package:shelf/shelf.dart';

import '../config/server_config.dart';

Middleware corsMiddleware() => (Handler inner) {
      return (Request request) async {
        if (request.method == 'OPTIONS') {
          return Response.ok('', headers: _corsHeaders);
        }
        final response = await inner(request);
        return response.change(headers: _corsHeaders);
      };
    };

const _corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PATCH, OPTIONS',
  'Access-Control-Allow-Headers': 'Origin, Content-Type, Accept, Authorization, X-API-Key',
};

Middleware dashboardAuth(ServerConfig config) {
  return (Handler inner) {
    if (config.dashboardApiKey.isEmpty) return inner;
    return (Request request) {
      final key = request.headers['x-api-key'] ?? request.headers['X-API-Key'];
      if (key != config.dashboardApiKey) {
        return Response.forbidden(
          '{"ok":false,"error":"Invalid API key"}',
          headers: {'Content-Type': 'application/json'},
        );
      }
      return inner(request);
    };
  };
}

Response jsonOk(Object body, {int status = 200}) => Response(
      status,
      body: body is String ? body : null,
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );

Response jsonErr(String message, {int status = 400}) =>
    Response(status, body: '{"ok":false,"error":"$message"}', headers: {'Content-Type': 'application/json'});

Future<String> readBody(Request request) => request.readAsString();

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
