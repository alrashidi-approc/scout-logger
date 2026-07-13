import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_theme.dart';
import '../widgets/scout_logo.dart';

/// Invalid, expired, or tampered share / notification link.
class LinkFallbackScreen extends StatelessWidget {
  const LinkFallbackScreen({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.bg,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [AppTheme.warning.withValues(alpha: 0.3), AppTheme.error.withValues(alpha: 0.2)],
                              ),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Icon(Icons.link_off_rounded, color: Colors.white, size: 32),
                          ),
                          const SizedBox(height: 22),
                          const Text(
                            'Link unavailable',
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            message ??
                                'This read-only link is invalid, expired, or was changed. Notification links cannot be edited — request a new one from your team.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 14, height: 1.55, color: Colors.white.withValues(alpha: 0.72)),
                          ),
                          const SizedBox(height: 28),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: AppTheme.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: () => context.go('/login'),
                              child: const Text('Sign in to Scout'),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextButton(
                            onPressed: () => context.go('/projects'),
                            child: Text('Go to dashboard', style: TextStyle(color: Colors.white.withValues(alpha: 0.8))),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    ScoutLogo(compact: true, iconSize: 28, onSidebar: true),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
