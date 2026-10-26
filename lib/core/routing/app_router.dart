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
