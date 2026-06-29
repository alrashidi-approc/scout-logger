import 'package:flutter/widgets.dart';
import 'package:url_launcher/link.dart';

/// Wraps a list row in a real `<a href>` on the web so plain clicks navigate
/// in-app while cmd/ctrl/middle/right-click open the route in a new browser tab.
class RouteLink extends StatelessWidget {
  const RouteLink({super.key, required this.path, required this.builder});

  final String path;
  final Widget Function(VoidCallback? open) builder;

  @override
  Widget build(BuildContext context) => Link(
        uri: Uri.parse(path),
        builder: (context, followLink) => builder(followLink),
      );
}
