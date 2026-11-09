import 'package:flutter/material.dart';
import 'package:locallink/app/app_dependencies.dart';
import 'package:locallink/core/routing/app_routes.dart';
import 'package:locallink/features/authentication/presentation/screens/welcome_screen.dart';
import 'package:locallink/features/home/presentation/screens/home_screen.dart';

/// Top-level route factory. Feature widgets remain responsible for their own
/// internal presentation, while application navigation is composed here.
class AppRouter {
  final AppDependencies dependencies;
  final Future<void> Function() onSaved;
  final Future<void> Function() onReset;
  final Future<void> Function()? onSignedOut;
  final ThemeMode Function() getThemeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  const AppRouter({
    required this.dependencies,
    required this.onSaved,
    required this.onReset,
    this.onSignedOut,
    required this.getThemeMode,
    required this.onThemeModeChanged,
  });

  /// Bundle 227 (F1): ONE start screen. Flutter splits '/home' into '/' +
  /// '/home' and kept a hidden Welcome under Home; `popUntil(isFirst)` (a
  /// notification tap, the new-friend chat) then removed Home and the next
  /// back / call end showed Welcome while logged in.
  static List<Route<dynamic>> oneStartScreen(
          String name, Route<dynamic> Function(RouteSettings) generate) =>
      [generate(RouteSettings(name: name))];

  /// Bundle 227 (F3): "back to Home first" stops at Home, never deeper.
  static bool isHomeOrFirst(Route<dynamic> route) =>
      route.settings.name == AppRoutes.home || route.isFirst;

  Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AppRoutes.home:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => HomeScreen(
            pairing: dependencies.pairing,
            api: dependencies.api,
            store: dependencies.store,
            messagingRepository: dependencies.messagingRepository,
            groupMessaging: dependencies.groupMessagingRepository,
            groupRepository: dependencies.groupRepository,
            files: dependencies.files,
            calls: dependencies.calls,
            crypto: dependencies.crypto,
            accountRepository: dependencies.account,
            identityRepository: dependencies.identity,
            connectivityController: dependencies.connectivity,
            onReset: onReset,
            onSignedOut: onSignedOut,
            restoreService: dependencies.restoreService,
            transferRepository: dependencies.transferRepository,
            homeRepository: dependencies.homeRepository,
            directoryRepository: dependencies.directoryRepository,
            adminRepositoryFactory: dependencies.adminRepositoryFactory,
            notifications: dependencies.notifications,
            viewMode: dependencies.viewMode,
            adminCapability: dependencies.adminCapability,
            authentication: dependencies.authentication,
            onSynced: () => dependencies.initializeConfiguredServices(),
            mesh: dependencies.mesh,
            themeMode: getThemeMode(),
            onThemeModeChanged: onThemeModeChanged,
          ),
        );
      case AppRoutes.welcome:
      default:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => WelcomeScreen(
            api: dependencies.api,
            store: dependencies.store,
            accountRepository: dependencies.account,
            authentication: dependencies.authentication,
            onSaved: onSaved,
            recoveryRepository: dependencies.recoveryRepository,
            transferRepository: dependencies.transferRepository,
            restorationService: dependencies.restoreService,
          ),
        );
    }
  }
}
