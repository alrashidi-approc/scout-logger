import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'config/app_config.dart';
import 'config/brand.dart';
import 'router/app_router.dart';
import 'services/auth_service.dart';
import 'services/dashboard_log_service.dart';
import 'services/dashboard_scope.dart';
import 'theme/app_theme.dart';
import 'theme/scroll_behavior.dart';
import 'widgets/page_placeholder.dart';
import 'widgets/web_copy_scope.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  await AppConfig.load();
  await AuthService.instance.load();

  final prevFlutter = FlutterError.onError;
  FlutterError.onError = (details) {
    DashboardLogService.record(
      projectId: DashboardScope.projectId,
      level: 'error',
      message: details.exceptionAsString(),
      context: {
        'library': details.library,
        if (details.context != null) 'context': details.context.toString(),
        if (details.stack != null) 'stack': details.stack.toString().split('\n').take(8).join('\n'),
      },
    );
    prevFlutter?.call(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    DashboardLogService.record(
      projectId: DashboardScope.projectId,
      level: 'error',
      message: error.toString(),
      context: {'stack': stack.toString().split('\n').take(5).join('\n')},
    );
    return false;
  };

  runApp(MaterialApp.router(
    title: Brand.name,
    theme: AppTheme.light().withScoutDefaults(),
    scrollBehavior: const ScoutScrollBehavior(),
    routerConfig: createRouter(),
    restorationScopeId: kIsWeb ? null : 'scout-dashboard',
    builder: (context, child) => ColoredBox(
      color: AppTheme.bg,
      child: ScoutSelectionShell(child: child ?? const ScoutBootstrapView()),
    ),
  ));
}
