/// Immutable application configuration shared by the Flutter client.
///
/// Values can be overridden at build time with `--dart-define` while keeping
/// safe local defaults for development and tests.
class AppConfig {
  final String appName;
  final String platform;
  final Duration defaultRequestTimeout;
  final Duration discoveryTimeout;
  final Duration uploadTimeout;
  final bool enableNetworkDiagnostics;
  final bool crashDiagnosticsEnabled;

  const AppConfig({
    this.appName = const String.fromEnvironment(
      'LOCLINK_APP_NAME',
      defaultValue: 'LocalLink',
    ),
    this.platform = const String.fromEnvironment(
      'LOCLINK_PLATFORM',
      defaultValue: 'android',
    ),
    this.defaultRequestTimeout = const Duration(seconds: 8),
    this.discoveryTimeout = const Duration(seconds: 3),
    this.uploadTimeout = const Duration(minutes: 3),
    this.enableNetworkDiagnostics = const bool.fromEnvironment(
      'LOCLINK_NETWORK_DIAGNOSTICS',
      defaultValue: false,
    ),
    this.crashDiagnosticsEnabled = const bool.fromEnvironment(
      'LOCLINK_CRASH_DIAGNOSTICS',
      defaultValue: true,
    ),
  });

  bool get isReleaseConfigured => const bool.fromEnvironment(
        'LOCLINK_RELEASE_CONFIGURED',
        defaultValue: false,
      );

  String get buildName => const String.fromEnvironment(
        'LOCLINK_BUILD_NAME',
        defaultValue: '0.27.0',
      );

  String get buildNumber => const String.fromEnvironment(
        'LOCLINK_BUILD_NUMBER',
        defaultValue: '32',
      );
}
