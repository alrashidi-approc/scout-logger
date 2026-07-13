import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Loads a deferred library once, then builds [builder].
class DeferredScreen extends StatefulWidget {
  const DeferredScreen({super.key, required this.loadLibrary, required this.builder});

  final Future<void> Function() loadLibrary;
  final Widget Function() builder;

  @override
  State<DeferredScreen> createState() => _DeferredScreenState();
}

class _DeferredScreenState extends State<DeferredScreen> {
  late final Future<void> _load = widget.loadLibrary();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _load,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const ColoredBox(
            color: AppTheme.bg,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return ColoredBox(
            color: AppTheme.bg,
            child: Center(child: Text('Failed to load screen: ${snapshot.error}', style: const TextStyle(color: AppTheme.muted))),
          );
        }
        return widget.builder();
      },
    );
  }
}
