import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/nav.dart';
import 'core/theme/tokens.dart';
import 'features/dashboard/dashboard_page.dart';
import 'features/editor/editor_page.dart';
import 'features/settings/settings_page.dart';
import 'features/trigger/trigger_page.dart';

/// App shell. Larm always uses the single dark Aurora glass theme; routes
/// are thin wrappers around the feature pages.
class LarmApp extends ConsumerWidget {
  const LarmApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Larm',
      navigatorKey: larmNavigatorKey,
      theme: larmGlassTheme,
      darkTheme: larmGlassTheme,
      themeMode: ThemeMode.dark,
      // One aurora backdrop behind every route, sheet and dialog.
      builder: (context, child) => Stack(
        children: [
          const Positioned.fill(child: AuroraBackdrop()),
          if (child != null) Positioned.fill(child: child),
        ],
      ),
      home: const DashboardPage(),
      onGenerateRoute: (routeSettings) {
        Map<String, Object?>? triggerArgs;
        final rawArgs = routeSettings.arguments;
        if (routeSettings.name == '/trigger' && rawArgs is Map) {
          triggerArgs = {
            'alarmId': rawArgs['alarmId'] as String?,
            'timerId': rawArgs['timerId'] as String?,
            'autoAction': rawArgs['autoAction'] as String?,
            'snoozeRemaining': rawArgs['snoozeRemaining'] as int?,
          };
        }
        switch (routeSettings.name) {
          case '/editor':
            String? alarmId;
            String? timerId;
            final args = routeSettings.arguments;
            if (args is Map) {
              alarmId = args['alarmId'] as String?;
              timerId = args['timerId'] as String?;
            }
            return MaterialPageRoute(
              settings: routeSettings,
              builder: (_) => EditorPage(alarmId: alarmId, timerId: timerId),
            );
          case '/trigger':
            final args = triggerArgs;
            return MaterialPageRoute(
              settings: routeSettings,
              builder: (_) => TriggerPage(
                alarmId: args?['alarmId'] as String?,
                timerId: args?['timerId'] as String?,
                autoAction: args?['autoAction'] as String?,
                snoozeRemaining: args?['snoozeRemaining'] as int?,
              ),
            );
          case '/settings':
            return MaterialPageRoute(
              settings: routeSettings,
              builder: (_) => const SettingsPage(),
            );
          default:
            return null;
        }
      },
    );
  }
}
