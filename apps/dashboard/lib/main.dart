import 'package:flutter/material.dart';

import 'config/app_config.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppConfig.load();
  runApp(MaterialApp.router(
    title: 'Scout Logger',
    theme: AppTheme.dark(),
    routerConfig: createRouter(),
    restorationScopeId: 'scout-dashboard',
  ));
}
