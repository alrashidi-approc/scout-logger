import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/date_range.dart';
import '../utils/responsive.dart';
import 'page_placeholder.dart';
export 'page_placeholder.dart' show PlaceholderLayout, ScoutAnimatedPlaceholder, ScoutRefreshShimmer, ScoutBootstrapView;
import 'period_picker.dart';

class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.period,
    this.onPeriodTap,
    this.actions,
  });

  final String title;
  final String? subtitle;
  final PeriodFilter? period;
  final VoidCallback? onPeriodTap;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < Breakpoints.mobile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(fontSize: compact ? 20 : 26, fontWeight: FontWeight.w800, color: AppTheme.text)),
        if (subtitle != null || period != null) ...[
          const SizedBox(height: 6),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              if (subtitle != null) Text(subtitle!, style: TextStyle(color: AppTheme.muted, fontSize: compact ? 12 : 13)),
              if (period != null) PeriodChip(period: period!, onTap: onPeriodTap),
            ],
          ),
        ],
        if (actions != null && actions!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 4, runSpacing: 4, children: actions!),
        ],
      ],
    );
  }
}

/// Strip `Exception:` prefix from API / load failures.
String formatLoadError(Object error) => error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');

/// Standard loading / error / content switch for scrollable screens.
class AsyncScreenBody extends StatelessWidget {
  const AsyncScreenBody({
    super.key,
    required this.loading,
    this.refreshing = false,
    this.error,
    required this.onRetry,
    required this.child,
    this.empty,
    this.placeholderLayout = PlaceholderLayout.list,
  });

  final bool loading;
  final bool refreshing;
  final Object? error;
  final VoidCallback onRetry;
  final Widget child;
  final Widget? empty;
  final PlaceholderLayout placeholderLayout;

  @override
  Widget build(BuildContext context) {
    if (loading) return ScoutAnimatedPlaceholder(layout: placeholderLayout);
    if (error != null && !refreshing) {
      return ErrorPanel(message: formatLoadError(error!), onRetry: onRetry);
    }
    if (empty != null && !refreshing) return empty!;

    return Stack(
      children: [
        child,
        if (refreshing)
          Positioned.fill(
            child: ColoredBox(
              color: AppTheme.bg.withValues(alpha: 0.92),
              child: ScoutRefreshShimmer(layout: placeholderLayout),
            ),
          ),
      ],
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.subtitle});

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 48, color: AppTheme.muted.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(subtitle!, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.muted)),
          ],
        ]),
      ),
    );
  }
}

class ErrorPanel extends StatelessWidget {
  const ErrorPanel({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline, color: AppTheme.error, size: 40),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.muted)),
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
      ]),
    );
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.layout = PlaceholderLayout.generic, this.refreshing = false});

  final PlaceholderLayout layout;
  final bool refreshing;

  @override
  Widget build(BuildContext context) =>
      refreshing ? ScoutRefreshShimmer(layout: layout) : ScoutAnimatedPlaceholder(layout: layout);
}
