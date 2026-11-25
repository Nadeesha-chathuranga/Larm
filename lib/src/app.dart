import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/nav.dart';
import 'core/notifications/fire_handoff.dart';
import 'core/theme/tokens.dart';
import 'features/dashboard/dashboard_page.dart';
import 'features/editor/editor_page.dart';
import 'features/settings/settings_page.dart';
import 'features/trigger/trigger_page.dart';

/// App shell. Larm always uses the single dark Aurora glass theme; routes
/// are thin wrappers around the feature pages.
class LarmApp extends ConsumerStatefulWidget {
  /// A fire queued before Flutter boot (locked cold start) becomes the first
  /// visible route so the dashboard never flashes over the alarm popup.
  const LarmApp({super.key, this.initialFire});

  final PendingFire? initialFire;

  @override
  ConsumerState<LarmApp> createState() => _LarmAppState();
}

class _LarmAppState extends ConsumerState<LarmApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FireHandoff.setDrainCallback(_drain);
    // A full-screen intent can fire while Flutter is still booting. Drain
    // again on the first frame, once the navigator key is attached.
    WidgetsBinding.instance.addPostFrameCallback((_) => _drain());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FireHandoff.clearDrainCallback(_drain);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A full-screen intent on an already-running app only resumes MainActivity;
    // drain here as well as on the notification callback.
    if (state == AppLifecycleState.resumed) _drain();
  }

  /// Opens every queued fire as the modal ringing page. Notification callbacks
  /// call this through [FireHandoff] so cold starts aren't lost.
  Future<void> _drain() async {
    if (!mounted) return;
    final navigator = larmNavigatorKey.currentState;
    if (navigator == null) return;
    await FireHandoff.drain((fire) async {
      if (!mounted) return false;
      navigator.pushNamed('/trigger', arguments: fire.arguments);
      return true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Larm',
      navigatorKey: larmNavigatorKey,
      theme: larmGlassTheme,
      darkTheme: larmGlassTheme,
      themeMode: ThemeMode.dark,
      // Keep the Android system navigation bar visible: every route is inset
      // above it, including the ringing popup and the + action.
      builder: (context, child) => Stack(
        children: [
          const Positioned.fill(child: AuroraBackdrop()),
          if (child != null)
            Positioned.fill(child: SafeArea(child: child)),
        ],
      ),
      initialRoute: widget.initialFire != null ? '/trigger' : '/',
      onGenerateInitialRoutes: (initialRoute) {
        final dashboard = _dashboardRoute();
        final fire = widget.initialFire;
        if (fire != null && initialRoute == '/trigger') {
          return [
            dashboard,
            _triggerRoute(
              RouteSettings(name: '/trigger', arguments: fire.arguments),
            ),
          ];
        }
        return [dashboard];
      },
      onGenerateRoute: _routeFor,
    );
  }

  MaterialPageRoute<dynamic> _dashboardRoute([RouteSettings? settings]) =>
      MaterialPageRoute<dynamic>(
        settings: settings ?? const RouteSettings(name: '/'),
        builder: (_) => const DashboardPage(),
      );

  MaterialPageRoute<dynamic> _triggerRoute(RouteSettings settings) {
    final rawArgs = settings.arguments;
    final args = rawArgs is Map<String, Object?>
        ? rawArgs
        : <String, Object?>{};
    // A fire is its own modal window above the dashboard, not a normal page.
    // Dismissing it reveals the previous route.
    return MaterialPageRoute<dynamic>(
      settings: settings,
      fullscreenDialog: true,
      builder: (_) => TriggerPage(
        alarmId: args['alarmId'] as String?,
        timerId: args['timerId'] as String?,
        autoAction: args['autoAction'] as String?,
        snoozeRemaining: args['snoozeRemaining'] as int?,
      ),
    );
  }

  Route<dynamic>? _routeFor(RouteSettings settings) {
    switch (settings.name) {
      case '/':
      case null:
        return _dashboardRoute(settings);
      case '/editor':
        String? alarmId;
        String? timerId;
        final args = settings.arguments;
        if (args is Map) {
          alarmId = args['alarmId'] as String?;
          timerId = args['timerId'] as String?;
        }
        return MaterialPageRoute<dynamic>(
          settings: settings,
          builder: (_) => EditorPage(alarmId: alarmId, timerId: timerId),
        );
      case '/trigger':
        return _triggerRoute(settings);
      case '/settings':
        return MaterialPageRoute<dynamic>(
          settings: settings,
          builder: (_) => const SettingsPage(),
        );
      default:
        return null;
    }
  }
}
