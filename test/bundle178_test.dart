// Bundle 178: LocalLink becomes LinkUp (visible name, logo A, app ID).
// Hidden storage / connection / code names are kept on purpose.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/config/app_config.dart';
import 'package:locallink/core/widgets/locallink_logo_mark.dart';

final _visibleOld = RegExp(r'\bLocalLink\b(?![A-Za-z0-9_\-])');
final _sq = RegExp(r"'(?:[^'\\\n]|\\.)*'");
final _dq = RegExp(r'"(?:[^"\\\n]|\\.)*"');

/// Quoted text with the old name, skipping comment lines and [keep] lines.
List<String> _oldNameInStrings(String dir, String ext,
    {bool singleQuotes = true, List<String> keep = const []}) {
  final hits = <String>[];
  for (final f in Directory(dir).listSync(recursive: true)) {
    if (f is! File || !f.path.endsWith(ext)) continue;
    final lines = f.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final t = line.trimLeft();
      if (t.startsWith('//') || t.startsWith('*') || t.startsWith('/*')) {
        continue;
      }
      if (keep.any(line.contains)) continue;
      final pats = singleQuotes ? [_sq, _dq] : [_dq];
      for (final p in pats) {
        for (final m in p.allMatches(line)) {
          if (_visibleOld.hasMatch(m.group(0)!)) {
            hits.add('${f.path}:${i + 1}: ${line.trim()}');
          }
        }
      }
    }
  }
  return hits;
}

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('LinkUp name', () {
    test('no visible "LocalLink" text left in the Dart app', () {
      final hits = _oldNameInStrings('lib', '.dart',
          keep: const ["static const String _name = 'LocalLink'"]); // log name
      expect(hits, isEmpty, reason: hits.join('\n'));
    });

    test('no visible "LocalLink" text left in Android code', () {
      final hits = _oldNameInStrings(
          'android/app/src/main/kotlin', '.kt',
          singleQuotes: false,
          keep: const [
            'INSTANCE_NAME', // Wi-Fi Direct service name (hidden, kept)
            'LocalLink-video-', // thread names (video code paused)
          ]);
      expect(hits, isEmpty, reason: hits.join('\n'));
    });

    test('app name, label and app ID', () {
      expect(const AppConfig().appName, 'LinkUp');
      expect(_read('android/app/src/main/AndroidManifest.xml'),
          contains('android:label="LinkUp"'));
      final gradle = _read('android/app/build.gradle');
      expect(gradle, contains('applicationId "com.sajjad.linkup"'));
      expect(gradle, contains('namespace "com.sajjad.locallink"'),
          reason: 'code folder name is kept');
      expect(_read('lib/app/local_link_app.dart'), contains("title: 'LinkUp'"));
    });

    test('Android notification categories and texts say LinkUp', () {
      final n = _read(
          'android/app/src/main/kotlin/com/sajjad/locallink/LocalLinkNotificationManager.kt');
      expect(n, contains('"LinkUp messages"'));
      expect(n, contains('"LinkUp system"'));
      final c = _read(
          'android/app/src/main/kotlin/com/sajjad/locallink/CallNotificationManager.kt');
      expect(c, contains('"LinkUp incoming calls"'));
      final s = _read(
          'android/app/src/main/kotlin/com/sajjad/locallink/LocalLinkTransportService.kt');
      expect(s, contains('"LinkUp is running"'));
    });
  });

  group('kept hidden names (nothing breaks, old phones still connect)', () {
    test('storage, keys and database names unchanged', () {
      expect(_read('lib/core/storage/database_encryption_service.dart'),
          contains("'locallink_db_key_v1'"));
      expect(_read('lib/core/storage/database_config.dart'),
          contains("'locallink.db'"));
      expect(_read('lib/core/services/identity_crypto_service.dart'),
          contains("'locallink_identity_x25519_seed_v1'"));
    });

    test('connection names unchanged', () {
      final tag = _read(
          'android/app/src/main/kotlin/com/sajjad/locallink/mesh/NearbyTagPolicy.kt');
      expect(tag, contains('SERVICE_TYPE = "_locallink._tcp"'));
      expect(tag, contains('INSTANCE_NAME = "LocalLink"'));
      expect(
          _read(
              'android/app/src/main/kotlin/com/sajjad/locallink/mesh/NearbyGroupPolicy.kt'),
          contains('NAME_PREFIX = "DIRECT-LL-"'));
      expect(_read('lib/features/directory/presentation/my_qr_screen.dart'),
          isNot(contains('linkup://')));
    });

    test('notification channel ids and log names unchanged', () {
      final n = _read(
          'android/app/src/main/kotlin/com/sajjad/locallink/LocalLinkNotificationManager.kt');
      // Bundle 282 (listed change): new tone = new message channel v5;
      // the old v4 id stays only to delete it.
      expect(n, contains('MESSAGE_CHANNEL_ID = "locallink_messages_v5"'));
      expect(n, contains('OLD_MESSAGE_CHANNEL_ID = "locallink_messages_v4"'));
      expect(n, contains('deleteNotificationChannel(OLD_MESSAGE_CHANNEL_ID)'));
      expect(n, contains('locallink_system_v4'));
      expect(
          _read(
              'android/app/src/main/kotlin/com/sajjad/locallink/CallNotificationActionReceiver.kt'),
          contains('"LocalLinkCall"'));
    });
  });

  group('logo A', () {
    testWidgets('logo mark paints with the LinkUp label', (tester) async {
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(body: Center(child: LocalLinkLogoMark(width: 96)))));
      expect(find.bySemanticsLabel('LinkUp logo'), findsOneWidget);
      final size = tester.getSize(find.byType(LocalLinkLogoMark));
      expect(size.width, 96);
      expect(size.height, closeTo(96 * 86 / 72, 0.01));
    });

    test('icon script and notification icon have the up arrow', () {
      final gen = _read('tool/generate_brand_assets.py');
      expect(gen, contains('U(74, 6)'), reason: 'arrow tip');
      expect(gen, contains('glyph_layer(size, 0.58, True)'));
      final icon = _read('android/app/src/main/res/drawable/ic_notification.xml');
      expect(icon, contains('LinkUp logo silhouette'));
      expect(icon, contains('android:fillType="evenOdd"'));
    });

    test('generated icons exist at every size', () {
      for (final d in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
        for (final f in [
          'ic_launcher.png',
          'ic_launcher_round.png',
          'ic_launcher_foreground.png'
        ]) {
          expect(File('android/app/src/main/res/mipmap-$d/$f').existsSync(),
              isTrue,
              reason: '$d/$f');
        }
      }
      expect(File('assets/brand/splash_logo.png').existsSync(), isTrue);
    });
  });
}
