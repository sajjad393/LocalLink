// Bundle 213: this app's build, sent to the server and to nearby phones.
//
// AppConfig.buildNumber is a --dart-define (default '32') and is not set by a
// plain `flutter build apk`, so it can't be trusted. These two constants are
// kept equal to pubspec.yaml `version:` (a test checks it).

const int kAppBuild = 131;
const String kAppVersion = '3.0.60';

/// HTTP header + socket header with the build (server version gate).
const String kAppBuildHeader = 'X-LinkUp-Build';

abstract final class AppBuild {
  /// Testers only (Admin panel > Nearby tests): "Pretend old build" makes
  /// this phone report one build lower, to try the version rule.
  static bool pretendOld = false;

  /// The build this phone reports to the server and nearby phones.
  static int get sent => pretendOld ? kAppBuild - 1 : kAppBuild;

  static String get sentVersion => pretendOld ? '$kAppVersion (test: old)' : kAppVersion;

  /// The server said 426 update_required (set by the version service).
  static void Function(String body)? onUpgradeRequired;

  static Map<String, String> withHeader(Map<String, String>? headers) => {
        ...?headers,
        kAppBuildHeader: '$sent',
      };
}
