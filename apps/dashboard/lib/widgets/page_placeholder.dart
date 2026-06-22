import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/responsive.dart';
import 'scout_logo.dart';

enum PlaceholderLayout {
  dashboard,
  events,
  issues,
  list,
  projects,
  detail,
  settings,
  geo,
  analytics,
  generic,
}

BoxDecoration dashboardPageDecoration() => const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFF8FAFC), Color(0xFFF1F5F9)],
      ),
    );

/// First paint while Flutter boots — branded pulse, no skeleton shimmer.
class ScoutBootstrapView extends StatefulWidget {
  const ScoutBootstrapView({super.key});

  @override
  State<ScoutBootstrapView> createState() => _ScoutBootstrapViewState();
}

class _ScoutBootstrapViewState extends State<ScoutBootstrapView> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: dashboardPageDecoration(),
      child: SafeArea(
        child: Center(
          child: FadeTransition(
            opacity: CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ScoutLogo(iconSize: 48),
                const SizedBox(height: 28),
                const _LoadingDots(),
                const SizedBox(height: 16),
                Text('Loading dashboard…', style: TextStyle(color: AppTheme.muted.withValues(alpha: 0.9), fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingDots extends StatefulWidget {
  const _LoadingDots();

  @override
  State<_LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<_LoadingDots> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final t = (_c.value + i * 0.2) % 1.0;
          final y = 4 * (t < 0.5 ? t * 2 : (1 - t) * 2);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Transform.translate(
              offset: Offset(0, -y),
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.35 + t * 0.45), shape: BoxShape.circle),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// Initial load — staggered fade/slide, no shimmer sweep.
class ScoutAnimatedPlaceholder extends StatelessWidget {
  const ScoutAnimatedPlaceholder({super.key, required this.layout});

  final PlaceholderLayout layout;

  @override
  Widget build(BuildContext context) {
    final pad = pagePad(context);
    return DecoratedBox(
      decoration: dashboardPageDecoration(),
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: pageInsets(context, top: pad, bottom: pad),
        children: [_EntranceBlock(index: 0, child: _layoutBody(context, layout))],
      ),
    );
  }

  Widget _layoutBody(BuildContext context, PlaceholderLayout layout) => switch (layout) {
        PlaceholderLayout.dashboard => const _DashboardBones(animated: true),
        PlaceholderLayout.events => const _EventsBones(animated: true),
        PlaceholderLayout.issues => const _IssuesBones(animated: true),
        PlaceholderLayout.geo => const _GeoBones(animated: true),
        PlaceholderLayout.analytics => const _AnalyticsBones(animated: true),
        PlaceholderLayout.projects => const _ProjectsBones(animated: true),
        PlaceholderLayout.detail => const _DetailBones(animated: true),
        PlaceholderLayout.settings => const _SettingsBones(animated: true),
        PlaceholderLayout.list || PlaceholderLayout.generic => const _ListBones(animated: true),
      };
}

/// Refresh overlay — per-screen shimmer layouts.
class ScoutRefreshShimmer extends StatelessWidget {
  const ScoutRefreshShimmer({super.key, required this.layout});

  final PlaceholderLayout layout;

  @override
  Widget build(BuildContext context) {
    final pad = pagePad(context);
    return DecoratedBox(
      decoration: dashboardPageDecoration(),
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: pageInsets(context, top: pad, bottom: pad),
        children: [
          _ShimmerScope(child: _layoutBody(context, layout)),
        ],
      ),
    );
  }

  Widget _layoutBody(BuildContext context, PlaceholderLayout layout) => switch (layout) {
        PlaceholderLayout.dashboard => const _DashboardBones(),
        PlaceholderLayout.events => const _EventsBones(),
        PlaceholderLayout.issues => const _IssuesBones(),
        PlaceholderLayout.geo => const _GeoBones(),
        PlaceholderLayout.analytics => const _AnalyticsBones(),
        PlaceholderLayout.projects => const _ProjectsBones(),
        PlaceholderLayout.detail => const _DetailBones(),
        PlaceholderLayout.settings => const _SettingsBones(),
        PlaceholderLayout.list || PlaceholderLayout.generic => const _ListBones(),
      };
}

// ─── Shimmer engine ───────────────────────────────────────────────────────────

class _ShimmerScope extends StatefulWidget {
  const _ShimmerScope({required this.child});

  final Widget child;

  @override
  State<_ShimmerScope> createState() => _ShimmerScopeState();
}

class _ShimmerScopeState extends State<_ShimmerScope> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment(-1.5 + _c.value * 3, 0),
          end: Alignment(-0.5 + _c.value * 3, 0),
          colors: const [Color(0xFFE2E8F0), Color(0xFFF8FAFC), Color(0xFFE2E8F0)],
          stops: const [0.2, 0.5, 0.8],
        ).createShader(bounds),
        child: child,
      ),
      child: widget.child,
    );
  }
}

// ─── Entrance animation ───────────────────────────────────────────────────────

class _EntranceBlock extends StatefulWidget {
  const _EntranceBlock({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_EntranceBlock> createState() => _EntranceBlockState();
}

class _EntranceBlockState extends State<_EntranceBlock> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.index * 60), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final anim = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: anim,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero).animate(anim),
        child: widget.child,
      ),
    );
  }
}

// ─── Bones ────────────────────────────────────────────────────────────────────

class _Bone extends StatelessWidget {
  const _Bone({this.width, this.height = 12, this.radius = 8, this.animated = false, this.index = 0});

  final double? width;
  final double height;
  final double radius;
  final bool animated;
  final int index;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppTheme.border),
      ),
    );
    if (!animated) return box;
    return _EntranceBlock(index: index, child: box);
  }
}

class _CardBone extends StatelessWidget {
  const _CardBone({required this.child, this.height, this.animated = false, this.index = 0});

  final Widget child;
  final double? height;
  final bool animated;
  final int index;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      height: height,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: child,
    );
    if (!animated) return card;
    return _EntranceBlock(index: index, child: card);
  }
}

class _DashboardBones extends StatelessWidget {
  const _DashboardBones({this.animated = false});

  final bool animated;

  @override
  Widget build(BuildContext context) {
    final compact = isMobile(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Bone(width: 200, height: 28, animated: animated, index: 0),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < (compact ? 4 : 6); i++)
              SizedBox(
                width: compact ? 140 : 160,
                child: _CardBone(height: 72, animated: animated, index: i + 1, child: _Bone(height: 36, animated: animated)),
              ),
          ],
        ),
        const SizedBox(height: 16),
        _CardBone(
          height: compact ? 200 : 260,
          animated: animated,
          index: 7,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Bone(width: 140, height: 12, animated: animated),
              const SizedBox(height: 16),
              _Bone(width: double.infinity, height: compact ? 150 : 200, radius: 12, animated: animated),
            ],
          ),
        ),
        _CardBone(
          height: 140,
          animated: animated,
          index: 8,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Bone(width: 120, height: 12, animated: animated),
              const SizedBox(height: 12),
              _Bone(width: double.infinity, height: 12, animated: animated),
              const SizedBox(height: 8),
              _Bone(width: double.infinity, height: 12, animated: animated),
            ],
          ),
        ),
      ],
    );
  }
}

class _EventsBones extends StatelessWidget {
  const _EventsBones({this.animated = false});

  final bool animated;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Bone(width: 120, height: 28, animated: animated, index: 0),
        const SizedBox(height: 10),
        _Bone(width: 200, height: 14, animated: animated, index: 1),
        const SizedBox(height: 16),
        _CardBone(
          height: 100,
          animated: animated,
          index: 2,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (var i = 0; i < 5; i++) _Bone(width: 72, height: 32, radius: 20, animated: animated)],
          ),
        ),
        for (var i = 0; i < 5; i++)
          _CardBone(
            height: 96,
            animated: animated,
            index: 3 + i,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  _Bone(width: 56, height: 20, radius: 6, animated: animated),
                  const Spacer(),
                  _Bone(width: 100, height: 10, animated: animated),
                ]),
                const SizedBox(height: 12),
                _Bone(width: double.infinity, height: 14, animated: animated),
                const SizedBox(height: 8),
                _Bone(width: 220, height: 10, animated: animated),
              ],
            ),
          ),
      ],
    );
  }
}

class _IssuesBones extends StatelessWidget {
  const _IssuesBones({this.animated = false});

  final bool animated;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Bone(width: 100, height: 28, animated: animated, index: 0),
        const SizedBox(height: 10),
        _Bone(width: 180, height: 14, animated: animated, index: 1),
        const SizedBox(height: 16),
        _CardBone(
          height: 88,
          animated: animated,
          index: 2,
          child: Row(
            children: [
              for (var i = 0; i < 3; i++) ...[if (i > 0) const SizedBox(width: 8), _Bone(width: 64, height: 28, radius: 14, animated: animated)],
              const Spacer(),
              _Bone(width: 120, height: 32, radius: 8, animated: animated),
            ],
          ),
        ),
        for (var i = 0; i < 4; i++)
          _CardBone(
            height: 92,
            animated: animated,
            index: 3 + i,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Bone(width: 4, height: 56, radius: 2, animated: animated),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Bone(width: double.infinity, height: 14, animated: animated),
                      const SizedBox(height: 8),
                      _Bone(width: 140, height: 10, animated: animated),
                      const SizedBox(height: 8),
                      Row(children: [
                        _Bone(width: 48, height: 18, radius: 6, animated: animated),
                        const SizedBox(width: 6),
                        _Bone(width: 56, height: 18, radius: 6, animated: animated),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ListBones extends StatelessWidget {
  const _ListBones({this.animated = false});

  final bool animated;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Bone(width: 180, height: 28, animated: animated, index: 0),
        const SizedBox(height: 10),
        _Bone(width: 240, height: 14, animated: animated, index: 1),
        const SizedBox(height: 16),
        for (var i = 0; i < 5; i++)
          _CardBone(
            height: 72,
            animated: animated,
            index: 2 + i,
            child: Row(
              children: [
                _Bone(width: 36, height: 36, radius: 10, animated: animated),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Bone(width: double.infinity, height: 14, animated: animated),
                      const SizedBox(height: 8),
                      _Bone(width: 160, height: 10, animated: animated),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ProjectsBones extends StatelessWidget {
  const _ProjectsBones({this.animated = false});

  final bool animated;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Bone(width: 140, height: 28, animated: animated, index: 0),
        const SizedBox(height: 10),
        _Bone(width: 300, height: 14, animated: animated, index: 1),
        const SizedBox(height: 20),
        _CardBone(
          height: 56,
          animated: animated,
          index: 2,
          child: Row(children: [
            Expanded(child: _Bone(height: 14, animated: animated)),
            const SizedBox(width: 12),
            _Bone(width: 80, height: 36, radius: 8, animated: animated),
          ]),
        ),
        for (var i = 0; i < 3; i++)
          _CardBone(
            height: 100,
            animated: animated,
            index: 3 + i,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Bone(width: 160, height: 16, animated: animated),
                const SizedBox(height: 12),
                _Bone(width: double.infinity, height: 10, animated: animated),
                const SizedBox(height: 8),
                _Bone(width: 120, height: 10, animated: animated),
              ],
            ),
          ),
      ],
    );
  }
}

class _GeoBones extends StatelessWidget {
  const _GeoBones({this.animated = false});

  final bool animated;

  @override
  Widget build(BuildContext context) {
    final compact = isMobile(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Bone(width: 140, height: 28, animated: animated, index: 0),
        const SizedBox(height: 16),
        _CardBone(
          height: compact ? 220 : 320,
          animated: animated,
          index: 1,
          child: Center(child: _Bone(width: compact ? 200 : 280, height: compact ? 120 : 180, radius: 12, animated: animated)),
        ),
        for (var i = 0; i < 4; i++)
          _CardBone(
            height: 52,
            animated: animated,
            index: 2 + i,
            child: Row(children: [
              _Bone(width: 28, height: 20, animated: animated),
              const SizedBox(width: 12),
              Expanded(child: _Bone(height: 12, animated: animated)),
              _Bone(width: 48, height: 12, animated: animated),
            ]),
          ),
      ],
    );
  }
}

class _AnalyticsBones extends StatelessWidget {
  const _AnalyticsBones({this.animated = false});

  final bool animated;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Bone(width: 120, height: 28, animated: animated, index: 0),
        const SizedBox(height: 12),
        Row(
          children: [
            for (var i = 0; i < 4; i++) ...[
              if (i > 0) const SizedBox(width: 16),
              _Bone(width: 72, height: 28, animated: animated),
            ],
          ],
        ),
        const SizedBox(height: 16),
        _CardBone(
          height: 200,
          animated: animated,
          index: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Bone(width: 100, height: 12, animated: animated),
              const SizedBox(height: 16),
              _Bone(width: double.infinity, height: 140, radius: 10, animated: animated),
            ],
          ),
        ),
        _CardBone(
          height: 120,
          animated: animated,
          index: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                _Bone(width: double.infinity, height: 12, animated: animated),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _DetailBones extends StatelessWidget {
  const _DetailBones({this.animated = false});

  final bool animated;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Bone(width: 80, height: 32, radius: 10, animated: animated, index: 0),
        const SizedBox(height: 16),
        _Bone(width: 220, height: 24, animated: animated, index: 1),
        const SizedBox(height: 12),
        _Bone(width: 300, height: 14, animated: animated, index: 2),
        const SizedBox(height: 20),
        _CardBone(
          height: 160,
          animated: animated,
          index: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Bone(width: 100, height: 12, animated: animated),
              const SizedBox(height: 12),
              _Bone(width: double.infinity, height: 14, animated: animated),
              const SizedBox(height: 8),
              _Bone(width: double.infinity, height: 14, animated: animated),
            ],
          ),
        ),
        for (var i = 0; i < 2; i++)
          _CardBone(
            height: 120,
            animated: animated,
            index: 4 + i,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Bone(width: 140, height: 12, animated: animated),
                const SizedBox(height: 12),
                _Bone(width: double.infinity, height: 12, animated: animated),
              ],
            ),
          ),
      ],
    );
  }
}

class _SettingsBones extends StatelessWidget {
  const _SettingsBones({this.animated = false});

  final bool animated;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Bone(width: 200, height: 28, animated: animated, index: 0),
        const SizedBox(height: 8),
        _Bone(width: 280, height: 14, animated: animated, index: 1),
        const SizedBox(height: 20),
        for (var i = 0; i < 3; i++)
          _CardBone(
            height: i == 0 ? 140 : 220,
            animated: animated,
            index: 2 + i,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Bone(width: i == 0 ? 120 : 160, height: 14, animated: animated),
                const SizedBox(height: 14),
                for (var j = 0; j < (i == 0 ? 2 : 4); j++) ...[
                  if (j > 0) const SizedBox(height: 10),
                  _Bone(width: double.infinity, height: 12, animated: animated),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
