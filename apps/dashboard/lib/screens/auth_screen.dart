import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../config/app_config.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/dashboard_footer.dart';
import '../widgets/scout_logo.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _rememberMe = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _rememberMe = AuthService.instance.rememberMe;
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AuthService.instance.login(
        email: _email.text.trim(),
        password: _password.text,
        rememberMe: _rememberMe,
      );
      if (mounted) context.go('/projects');
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Sign in',
      subtitle: 'Access your Scout projects and DSN credentials.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(labelText: 'Email'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: true,
          autofillHints: const [AutofillHints.password],
          decoration: const InputDecoration(labelText: 'Password'),
          onSubmitted: (_) => _submit(),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('Keep me signed in'),
          subtitle: const Text('Stay logged in on this device for 30 days'),
          value: _rememberMe,
          onChanged: _loading ? null : (v) => setState(() => _rememberMe = v ?? true),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: AppTheme.error, fontSize: 13)),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _loading ? null : _submit,
          child: _loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Sign in'),
        ),
        const SizedBox(height: 16),
        TextButton(onPressed: () => context.go('/signup'), child: const Text('Create an account')),
      ]),
    );
  }
}

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await AuthService.instance.signup(
        email: _email.text.trim(),
        password: _password.text,
        displayName: _name.text.trim(),
      );
      if (!mounted) return;
      if (result['verificationRequired'] == true) {
        context.go('/verify-email?email=${Uri.encodeComponent(_email.text.trim())}');
        if (result['devVerificationUrl'] != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Dev verify link: ${result['devVerificationUrl']}')),
          );
        }
      } else {
        if (mounted) context.go('/projects');
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Create account',
      subtitle: AppConfig.I.emailVerification
          ? 'First user becomes admin. You will receive a verification email before signing in.'
          : 'First user becomes admin. Email verification is off — you can sign in right after signup.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name (optional)')),
        const SizedBox(height: 12),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Email'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Password (min 8 characters)'),
          onSubmitted: (_) => _submit(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: AppTheme.error, fontSize: 13)),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _loading ? null : _submit,
          child: _loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Sign up'),
        ),
        const SizedBox(height: 16),
        TextButton(onPressed: () => context.go('/login'), child: const Text('Already have an account? Sign in')),
      ]),
    );
  }
}

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key, this.email, this.token});

  final String? email;
  final String? token;

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final _token = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _info;

  @override
  void initState() {
    super.initState();
    if (widget.token != null) {
      _token.text = widget.token!;
      WidgetsBinding.instance.addPostFrameCallback((_) => _verify());
    }
  }

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final value = _token.text.trim();
    if (value.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AuthService.instance.verifyEmail(value);
      if (mounted) context.go('/projects');
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    final email = widget.email;
    if (email == null || email.isEmpty) return;
    setState(() => _loading = true);
    try {
      final link = await AuthService.instance.resendVerification(email);
      if (mounted) {
        setState(() => _info = link == null ? 'Verification email sent.' : 'Dev link: $link');
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Verify email',
      subtitle: widget.email == null ? 'Paste the token from your verification email.' : 'We sent a link to ${widget.email}.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(controller: _token, decoration: const InputDecoration(labelText: 'Verification token')),
        if (_info != null) ...[
          const SizedBox(height: 12),
          Text(_info!, style: const TextStyle(color: AppTheme.success, fontSize: 13)),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: AppTheme.error, fontSize: 13)),
        ],
        const SizedBox(height: 20),
        FilledButton(onPressed: _loading ? null : _verify, child: const Text('Verify & continue')),
        if (widget.email != null) ...[
          const SizedBox(height: 12),
          TextButton(onPressed: _loading ? null : _resend, child: const Text('Resend verification email')),
        ],
        const SizedBox(height: 8),
        TextButton(onPressed: () => context.go('/login'), child: const Text('Back to sign in')),
      ]),
    );
  }
}

class AuthScaffold extends StatelessWidget {
  const AuthScaffold({super.key, required this.title, required this.subtitle, required this.child});

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 720;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(compact ? 20 : 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(child: ScoutLogo(showTagline: true, iconSize: 48)),
                      const SizedBox(height: 32),
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: AppTheme.panel,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppTheme.border),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, 8))],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
                            const SizedBox(height: 6),
                            Text(subtitle, style: const TextStyle(color: AppTheme.muted, fontSize: 13, height: 1.4)),
                            const SizedBox(height: 20),
                            child,
                          ],
                        ),
                      ),
                      const AuthFooter(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
