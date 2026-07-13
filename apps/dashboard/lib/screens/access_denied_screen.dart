import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_theme.dart';
import '../widgets/scout_logo.dart';

/// Shown when a signed-in user lacks project access or role.
class AccessDeniedScreen extends StatelessWidget {
  const AccessDeniedScreen({super.key, this.projectId, this.reason});

  final String? projectId;
  final String? reason;

  @override
  Widget build(BuildContext context) {
    final isRole = reason == 'role';
    return Material(
      color: AppTheme.bg,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF8FAFC), Color(0xFFEFF6FF)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.border),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primary.withValues(alpha: 0.08),
                            blurRadius: 32,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: AppTheme.error.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(
                              isRole ? Icons.lock_outline : Icons.folder_off_outlined,
                              color: AppTheme.error,
                              size: 28,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            isRole ? 'Insufficient permissions' : 'Project access denied',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppTheme.text),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            isRole
                                ? 'Your role on this project does not include this page. Ask the project owner for access.'
                                : 'You are signed in but not a member of this project. Request an invite from the owner.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 14, height: 1.5, color: AppTheme.muted),
                          ),
                          if (projectId != null) ...[
                            const SizedBox(height: 16),
                            Text(
                              projectId!,
                              style: TextStyle(fontSize: 11, color: AppTheme.muted.withValues(alpha: 0.85), fontFamily: 'monospace'),
                            ),
                          ],
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => context.go('/login'),
                                  child: const Text('Switch account'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton(
                                  onPressed: () => context.go('/projects'),
                                  child: const Text('My projects'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    const ScoutLogo(compact: true, iconSize: 28),
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
