import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../config/server_config.dart';
import '../middleware/http_utils.dart';
import '../services/email_service.dart';
import '../services/jwt_service.dart';
import '../store/auth_store.dart';

Handler authRoutes({
  required ServerConfig config,
  required AuthStore auth,
  required JwtService jwt,
  required EmailService email,
}) {
  final router = Router();

  router.post('/signup', (Request request) async {
    try {
      final body = jsonDecode(await readBody(request)) as Map<String, dynamic>;
      final emailAddr = body['email']?.toString() ?? '';
      final password = body['password']?.toString() ?? '';
      final name = body['displayName']?.toString();
      final autoVerify = !email.enabled;
      final user = await auth.signup(email: emailAddr, password: password, displayName: name, autoVerify: autoVerify);
      String? devLink;
      String? jwtToken;
      if (!autoVerify) {
        final token = await auth.createVerificationToken(user['id'] as String);
        devLink = await email.sendVerification(to: user['email'] as String, token: token);
      } else {
        jwtToken = jwt.sign(auth.toPrincipal(user), rememberMe: true);
      }
      return Response.ok(
        jsonEncode({
          'ok': true,
          'user': auth.publicUser(user),
          'verificationRequired': !autoVerify,
          if (jwtToken != null) 'token': jwtToken,
          if (devLink != null) 'devVerificationUrl': devLink,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } on ArgumentError catch (e) {
      return jsonErr(e.message ?? '$e');
    } catch (e) {
      return jsonErr('$e', status: 500);
    }
  });

  router.post('/login', (Request request) async {
    try {
      final body = jsonDecode(await readBody(request)) as Map<String, dynamic>;
      final emailAddr = body['email']?.toString().trim().toLowerCase() ?? '';
      final password = body['password']?.toString() ?? '';
      final user = await auth.findUserByEmail(emailAddr);
      if (user == null || !auth.verifyPassword(password, user['passwordHash'] as String)) {
        return jsonErr('Invalid email or password', status: 401);
      }
      if (user['emailVerified'] != true) {
        return jsonErr('Verify your email before signing in', status: 403);
      }
      final rememberMe = body['rememberMe'] != false;
      final principal = auth.toPrincipal(user);
      final token = jwt.sign(principal, rememberMe: rememberMe);
      return Response.ok(
        jsonEncode({'ok': true, 'token': token, 'user': auth.publicUser(user), 'rememberMe': rememberMe}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return jsonErr('$e', status: 500);
    }
  });

  router.post('/verify-email', (Request request) async {
    try {
      final body = jsonDecode(await readBody(request)) as Map<String, dynamic>;
      final token = body['token']?.toString() ?? '';
      if (token.isEmpty) return jsonErr('token is required');
      final user = await auth.verifyEmail(token);
      if (user == null) return jsonErr('Invalid or expired token', status: 400);
      final principal = auth.toPrincipal(user);
      final jwtToken = jwt.sign(principal, rememberMe: true);
      return Response.ok(
        jsonEncode({'ok': true, 'token': jwtToken, 'user': auth.publicUser(user), 'rememberMe': true}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return jsonErr('$e', status: 500);
    }
  });

  router.post('/refresh', (Request request) async {
    try {
      final bearer = bearerToken(request);
      if (bearer == null || bearer.isEmpty) return jsonErr('Unauthorized', status: 401);
      final principal = jwt.verify(bearer);
      if (principal == null || principal.userId == null) return jsonErr('Unauthorized', status: 401);

      final body = jsonDecode(await readBody(request)) as Map<String, dynamic>;
      final rememberMe = body['rememberMe'] == true || jwt.rememberMeFromToken(bearer) == true;

      final user = await auth.findUserById(principal.userId!);
      if (user == null || user['emailVerified'] != true) return jsonErr('Unauthorized', status: 401);

      final token = jwt.sign(auth.toPrincipal(user), rememberMe: rememberMe);
      return Response.ok(
        jsonEncode({'ok': true, 'token': token, 'user': auth.publicUser(user), 'rememberMe': rememberMe}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return jsonErr('$e', status: 500);
    }
  });

  router.post('/resend-verification', (Request request) async {
    try {
      final body = jsonDecode(await readBody(request)) as Map<String, dynamic>;
      final emailAddr = body['email']?.toString().trim().toLowerCase() ?? '';
      final user = await auth.findUserByEmail(emailAddr);
      if (user == null) return jsonOk('{"ok":true}');
      if (user['emailVerified'] == true) return jsonOk('{"ok":true}');
      final token = await auth.createVerificationToken(user['id'] as String);
      final devLink = await email.sendVerification(to: user['email'] as String, token: token);
      return Response.ok(
        jsonEncode({'ok': true, if (devLink != null) 'devVerificationUrl': devLink}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return jsonErr('$e', status: 500);
    }
  });

  return router.call;
}
