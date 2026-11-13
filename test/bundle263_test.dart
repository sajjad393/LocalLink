// Bundle 263 (3.0.80+151): messages a normal user does not need are gone;
// the work behind them runs by itself; the security code note is in the
// chat like WhatsApp. See TODO_263.md.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/diagnostics/app_log_file.dart';
import 'package:locallink/core/diagnostics/ui_hidden_263.dart';
import 'package:locallink/core/security/security_code_245.dart';
import 'package:locallink/features/authentication/data/services/offline_publish_ticker_256.dart';
import 'package:locallink/features/directory/domain/directory_models.dart';

DirectoryProfile _card(String key, {String device = 'android-ali', String user = 'u-ali'}) =>
    DirectoryProfile(
      userId: user,
      deviceId: device,
      displayName: 'Ali',
      signingPublicKey: key,
      identityPublicKey: 'id',
      signature: 'sig',
      profileVersion: 1,
    );

String _src(String path) => File(path).readAsStringSync();
String _logs() => AppLogFile.instance.pendingForTest.join('\n');

const _home = 'lib/features/home/presentation/screens/home_screen.dart';
const _chat = 'lib/features/messaging/presentation/screens/chat_screen.dart';
const _account = 'lib/features/account/presentation/screens/account_center_screen.dart';
const _add = 'lib/features/directory/presentation/add_contact_screen.dart';
const _nearby = 'lib/features/directory/presentation/nearby_people_section.dart';
const _setup = 'lib/features/authentication/presentation/screens/setup_screen.dart';

void main() {
  final settings = <String, String>{};
  final hub = SecurityCode245.instance;

  Future<void> load() =>
      hub.load(read: (k) async => settings[k], write: (k, v) async => settings[k] = v);

  setUp(() {
    AppLogFile.instance.resetForTest();
    UiHidden263.resetForTest();
    settings.clear();
    hub.resetForTest();
  });

  tearDown(() => hub.resetForTest());

  group('A: Chats tab', () {
    final src = _src(_home);
    test('A-1 no "carried by N phones" card, a log line instead', () {
      expect(src, isNot(contains('JoinCard218.carried222(')));
      expect(src, contains("UiHidden263.note('carried', 'n=\${st.carriers}')"));
    });
    test('A-2 no "Account saved - Publish" banner', () {
      expect(src, isNot(contains('_offlineAccountBanner')));
      expect(src, isNot(contains('offline_publish_button')));
      expect(src, isNot(contains('it will publish itself automatically')));
      expect(src, contains("UiHidden263.note('publish')"));
    });
    test('A-3 no "Waiting for the server to be updated"; admin / code cards stay', () {
      expect(src, contains('_block218 != OfflineAccountSyncService.waitServerBlock236'));
      expect(src, contains('JoinCard218.stuck(block: _block218, onTry: _tryAgain218)'));
      expect(src, contains("UiHidden263.note('wait_server')"));
    });
    test('A-4 only the name note of "You\'re on the server now"', () {
      expect(src, contains("if (_join218 != null && _join218!['kind']?.toString() == 'renamed')"));
      expect(src, contains("if (join != null && join['kind']?.toString() != 'renamed') {"));
      expect(src, contains("UiHidden263.note('done', 'kind=\${join['kind'] ?? ''}')"));
    });
    test('A-5 no sync chip, A-6 no "Account published" snack', () {
      expect(src, isNot(contains('_gatedSyncNotice')));
      expect(src, isNot(contains('class _SyncNotice')));
      expect(src, isNot(contains('Account published to the server.')));
      expect(src, contains("UiHidden263.note('sync_notice')"));
    });
    test('A-7 the cards that need an action stay', () {
      expect(src, contains("'pwd_reset_only_here_222'"));
      expect(src, contains('JoinCard218.recovery('));
      expect(src, contains('const AdminBlockedBanner(),'));
      expect(src, contains('const SessionDeadBanner262(),'));
      expect(src, contains('const VersionBanner(),'));
      expect(src, contains('const NearbyReadyCard(),'));
    });
  });

  group('B: other server / technical messages', () {
    test('B-1/B-2 profile snacks are the same online or not', () {
      final p = _src('lib/features/account/presentation/screens/profile_screen.dart');
      expect(p, isNot(contains('it will sync when available')));
      // Bundle 289 (listed change): same words, new toast look.
      expect(p, contains("LinkToast.show(context, 'Profile saved', kind: LinkToastKind.done)"));
      final c = _src('lib/features/account/presentation/widgets/private_profile_card.dart');
      expect(c, isNot(contains('will update when online')));
    });
    test('B-3/B-4 Account: no phone-only box, no Find server now, no offline box', () {
      final s = _src(_account);
      expect(s, isNot(contains('_phoneOnly256')));
      expect(s, isNot(contains('Find server now')));
      expect(s, isNot(contains("ValueKey('account_offline_box')")));
      expect(s, contains("OfflinePublishTicker256.instance.nudge('account_open');"));
    });
    test('B-5 Add friend: no server status line, tries by itself on open', () {
      final s = _src(_add);
      expect(s, isNot(contains('_status256()')));
      expect(s, isNot(contains('AddStatusLine256(')));
      expect(s, contains("ticker.nudge('add_open');"));
      expect(s, contains('if (mounted) _autoFind263();'));
    });
    test('B-6 Add sheet: no device id row', () {
      final s = _src(_nearby);
      expect(s, isNot(contains('Copy device id')));
      expect(s, isNot(contains("'device …\$tail'")));
      expect(s, isNot(contains('Device id copied')));
    });
    test('B-7/B-8/B-9 sign-up: no dialog, plain spinner words, no history snack', () {
      final s = _src(_setup);
      expect(s, isNot(contains('_savedOnPhone256')));
      expect(s, isNot(contains('Looking for the LinkUp server')));
      expect(s, isNot(contains("'Server found'")));
      expect(s, isNot(contains('Could not check your account history')));
      expect(s, contains("'Creating your account…' : 'Signing you in…'"));
      expect(s, contains("UiHidden263.note('signup_saved')"));
      expect(s, contains("AppLogger.warning('RESTORE_MANIFEST'"));
    });
  });

  group('C: security code note in the chat (WhatsApp style)', () {
    test('C-1 a waiting change makes a waiting note; proof turns it into one taken note',
        () async {
      await load();
      await hub.noteCardChange(_card('k1'), _card('k2'));
      var ev = hub.eventsFor('android-ali');
      expect(ev, hasLength(1));
      expect(ev.single.waiting, isTrue);
      await hub.autoTake258(_card('k1'), _card('k2'), 'owner');
      ev = hub.eventsFor('android-ali');
      expect(ev, hasLength(1), reason: 'one note per change, not two');
      expect(ev.single.waiting, isFalse);
      expect(_logs(), contains('KEY_EVENT_263|user=u-ali waiting=y'));
      expect(_logs(), contains('was_waiting=y'));
      final saved = jsonDecode(settings[SecurityCode245.eventsSettingKey]!) as List;
      expect(saved, hasLength(1));
    });

    test('C-1 the note stays after the code page was opened', () async {
      await load();
      await hub.autoTake258(_card('k1'), _card('k2'), 'server');
      await hub.autoSeen258('android-ali');
      expect(hub.autoFor('android-ali'), isNull);
      expect(hub.eventsFor('android-ali'), hasLength(1));
    });

    test('C-1 at most 20 notes per person, older than a year dropped', () async {
      final old = DateTime.now().toUtc().subtract(const Duration(days: 400));
      settings[SecurityCode245.eventsSettingKey] = jsonEncode([
        KeyEvent263(userId: 'u-ali', oldDeviceId: 'a', deviceId: 'android-ali', at: old).toJson(),
      ]);
      await load();
      expect(hub.eventsFor('android-ali'), hasLength(1), reason: 'loaded as kept');
      for (var i = 0; i < 25; i++) {
        await hub.autoTake258(_card('k$i'), _card('k${i + 1}'), 'owner');
      }
      final ev = hub.eventsFor('android-ali');
      expect(ev, hasLength(SecurityCode245.maxEventsPerUser));
      expect(ev.any((e) => e.at == old), isFalse);
    });

    test('C-2 first start after the update: made from the kept changes', () async {
      final at = DateTime.now().toUtc().subtract(const Duration(hours: 3));
      settings[SecurityCode245.autoSettingKey] = jsonEncode({
        'u-ali': {'old_device_id': 'android-old', 'device_id': 'android-ali', 'at': at.toIso8601String()},
      });
      await load();
      final ev = hub.eventsFor('android-old');
      expect(ev, hasLength(1));
      expect(ev.single.waiting, isFalse);
      expect(settings[SecurityCode245.eventsSettingKey], isNotNull);
      // A second start does not add it again.
      await load();
      expect(hub.eventsFor('android-ali'), hasLength(1));
    });

    test('C-3 eventsFor matches the old phone, the new phone and the user id', () async {
      await load();
      await hub.autoTake258(_card('k1', device: 'android-old'), _card('k2', device: 'android-new'), 'owner');
      expect(hub.eventsFor('android-old'), hasLength(1));
      expect(hub.eventsFor('android-new'), hasLength(1));
      expect(hub.eventsFor('x', userId: 'u-ali'), hasLength(1));
      expect(hub.eventsFor('android-other'), isEmpty);
    });

    test('C-4 place: between the messages around its time, or under the last one', () {
      final t = DateTime.utc(2026, 11, 12, 10);
      final e1 = KeyEvent263(userId: 'u', oldDeviceId: '', deviceId: 'd', at: t.add(const Duration(minutes: 5)));
      final e2 = KeyEvent263(userId: 'u', oldDeviceId: '', deviceId: 'd', at: t.add(const Duration(minutes: 20)));
      final m1 = t;
      final m2 = t.add(const Duration(minutes: 10));
      expect(KeyEvent263.between([e1, e2], null, m1), isEmpty);
      expect(KeyEvent263.between([e1, e2], m1, m2), [e1]);
      expect(KeyEvent263.after([e1, e2], m2), [e2]);
      // A note at the very time of a message shows above it.
      expect(KeyEvent263.between([e1], m1, e1.at), [e1]);
    });

    test('C-5..7 chat wiring: no bar on top, pills in the list, tap = code page, none in search',
        () {
      final s = _src(_chat);
      expect(s, isNot(contains('_keyChangeBanner245(context, device), // Bundle 245')));
      expect(s, contains('keyEventsBefore263(keyEvents, visibleMessages, index)'));
      expect(s, contains('keyEventsAfterLast263(keyEvents, visibleMessages)'));
      expect(s, contains("Tap to learn more."));
      expect(s, contains("Tap to check."));
      expect(s, contains('onTap: () => _openSecurityCode245(device),'));
      expect(s, contains('final keyEvents = searchQuery.isEmpty'));
      expect(s, contains('SecurityCode245.instance.addListener(_onKeys263);'));
      expect(s, contains('SecurityCode245.instance.removeListener(_onKeys263);'));
    });
  });

  group('F: the work runs by itself', () {
    test('F-1 open / pull nudges reach the phone-only upload', () async {
      final whys = <String>[];
      final t = OfflinePublishTicker256.instance;
      t.start((why) async => whys.add(why), listenLifecycle: false);
      addTearDown(t.stop);
      t.nudge('add_open');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(whys, contains('add_open'));
      expect(_src(_home), contains("OfflinePublishTicker256.instance.nudge('refresh');"));
    });

    test('F-2 a hidden card writes its log line once', () {
      UiHidden263.note('carried', 'n=2');
      UiHidden263.note('carried', 'n=3');
      final lines = _logs().split('\n').where((l) => l.contains('UI_HIDDEN_263')).toList();
      expect(lines, hasLength(1));
      expect(lines.single, contains('UI_HIDDEN_263|card=carried n=2'));
    });
  });
}
