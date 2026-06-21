import 'package:flutter/material.dart';

import 'config/app_config.dart';
import 'router/app_router.dart';
import 'services/auth_service.dart';
import 'theme/app_theme.dart';
import 'theme/scroll_behavior.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppConfig.load();
  await AuthService.instance.load();
  runApp(MaterialApp.router(
    title: 'Scout Logger',
    theme: AppTheme.light().withScoutDefaults(),
    scrollBehavior: const ScoutScrollBehavior(),
    routerConfig: createRouter(),
    restorationScopeId: 'scout-dashboard',
  ));
}
