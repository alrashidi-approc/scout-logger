import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../utils/clipboard.dart';

/// Enables text selection and routes web keyboard copy through a reliable
/// clipboard helper (Flutter's [Clipboard.setData] is unreliable on web).
class ScoutSelectionShell extends StatefulWidget {
  const ScoutSelectionShell({super.key, required this.child});

  final Widget child;

  @override
  State<ScoutSelectionShell> createState() => _ScoutSelectionShellState();
}

class _ScoutSelectionShellState extends State<ScoutSelectionShell> {
  String? _selectedText;

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      onSelectionChanged: (content) => _selectedText = content?.plainText,
      child: kIsWeb
          ? Actions(
              actions: {
                CopySelectionTextIntent: CallbackAction<CopySelectionTextIntent>(
                  onInvoke: (_) {
                    final text = _selectedText;
                    if (text == null || text.isEmpty) return null;
                    copyToClipboard(text);
                    return null;
                  },
                ),
              },
              child: widget.child,
            )
          : widget.child,
    );
  }
}
