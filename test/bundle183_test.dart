// Bundle 183: Settings, Account and the 4 tabs - one style, plain words.
//
// F1-F11 (Settings / Account) and T1-T7 (tabs) from TODO_183.md.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:locallink/core/models/call.dart';
import 'package:locallink/core/models/profile.dart';
import 'package:locallink/core/notifications/local_link_notification_service.dart';
import 'package:locallink/core/presence/presence_hub.dart';
import 'package:locallink/core/presence/block_hub.dart';
import 'package:locallink/features/directory/data/friend_requests.dart';
import 'package:locallink/core/widgets/blocked_pill.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/state/app_view_mode.dart';
import 'package:locallink/core/theme/app_theme.dart';
import 'package:locallink/core/widgets/messenger_list_group.dart';
import 'package:locallink/core/widgets/tab_top_bar.dart';
import 'package:locallink/features/account/domain/account_repository_contract.dart';
import 'package:locallink/features/account/domain/identity_repository_contract.dart';
import 'package:locallink/features/account/presentation/screens/account_center_screen.dart';
import 'package:locallink/features/admin/data/services/admin_capability_service.dart';
import 'package:locallink/features/admin/domain/admin_repository_factory.dart';
import 'package:locallink/features/calls/bloc/call_bloc.dart' hide CallState;
import 'package:locallink/features/calls/presentation/screens/calls_screen.dart';
import 'package:locallink/features/connectivity/bloc/connectivity_bloc.dart';
import 'package:locallink/features/connectivity/bloc/mesh_bloc.dart';
import 'package:locallink/features/connectivity/data/services/nearby_experiments.dart';
import 'package:locallink/features/connectivity/domain/mesh_repository_contract.dart';
import 'package:locallink/features/directory/data/services/pairing_service.dart';
import 'package:locallink/features/directory/domain/directory_models.dart';
import 'package:locallink/features/directory/domain/directory_repository_contract.dart';
import 'package:locallink/features/directory/presentation/contacts_screen.dart';
import 'package:locallink/features/files/domain/file_transfer_repository_contract.dart';
import 'package:locallink/features/groups/domain/group_messaging_repository_contract.dart';
import 'package:locallink/features/home/presentation/screens/messenger_settings_screen.dart';
import 'package:locallink/features/messaging/domain/messaging_repository_contract.dart';
import 'package:locallink/features/recovery/domain/account_restoration_repository_contract.dart';
import 'package:locallink/features/transfer/domain/account_transfer_repository_contract.dart';

import 'call_fix_146_test.dart'
    show FakeGateway, HistoryRepository, FakeConnectivityRepository;
import 'support/phase5_fakes.dart' show FakePeerTransport;

String _src(String path) => File(path).readAsStringSync();

// ----------------------------------------------------------------- fakes

class _Store extends LocalStore {
  @override
  String? get username => 'sajjad';
  @override
  String? get deviceName => 'My LinkUp phone';
  @override
  bool get isOfflinePending => false;
  @override
  Map<String, dynamic>? get offlinePending => null;
}

class _Api implements LocalLinkApi {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Crypto implements IdentityCryptoService {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Identity implements IdentityRepositoryContract {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Restore implements AccountRestorationRepositoryContract {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Transfer implements AccountTransferRepositoryContract {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _AdminFactory implements AdminRepositoryFactory {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Messaging implements MessagingRepositoryContract {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Groups implements GroupMessagingRepositoryContract {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Files implements FileTransferRepositoryContract {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Mesh implements MeshRepositoryContract {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Account implements AccountRepositoryContract {
  Object? error;
  int loads = 0;

  @override
  Future<AccountProfileLoadResult> loadProfile() async {
    loads++;
    return AccountProfileLoadResult(
      cached: const LocalProfile(
          userId: 'u1', username: 'sajjad', displayName: 'sajjad'),
      error: error,
    );
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Bundle 196: records the Private profile save.
class _SavingAccount extends _Account {
  final List<bool> savedByName = <bool>[];
  @override
  Future<AccountProfileSaveResult> saveProfile(
      {required String displayName,
      required String username,
      File? avatarFile,
      String phoneNumber = '',
      String phoneVisibility = 'contacts',
      bool discoverableByPhone = true,
      bool discoverableByName = true,
      bool directorySyncEnabled = true}) async {
    savedByName.add(discoverableByName);
    return AccountProfileSaveResult(
        profile: LocalProfile(
            userId: 'u1',
            username: username,
            displayName: displayName,
            discoverableByName: discoverableByName),
        synced: true);
  }
}

class _Directory implements DirectoryRepositoryContract {
  _Directory(this.list);
  final List<DirectoryProfile> list;

  @override
  Stream<DirectoryProfile> get profileUpdates => const Stream.empty();
  @override
  Future<List<DirectoryProfile>> contacts() async => list;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

// ----------------------------------------------------------------- hosts

/// The tabs are opened ON TOP of the start screen (like the real app), so a
/// screen that lets Flutter add an arrow by itself WOULD show one here.
Future<void> _pushed(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(1080, 2280);
  tester.view.devicePixelRatio = 3; // 360 x 760, the mock's phone
  addTearDown(tester.view.reset);
  final nav = GlobalKey<NavigatorState>();
  await tester.pumpWidget(MaterialApp(
    theme: LocalLinkTheme.light(),
    navigatorKey: nav,
    home: const Scaffold(body: Text('start')),
  ));
  nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => screen));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

final _viewMode = AppViewModeCubit();
final _connectivity =
    ConnectivityBloc(repository: FakeConnectivityRepository());
final _calls = CallBloc(service: FakeGateway(), repository: HistoryRepository());

LocalLinkNotificationService _notifications(LocalStore store) =>
    LocalLinkNotificationService(
      store: store,
      messaging: _Messaging(),
      groups: _Groups(),
      calls: _calls,
    );

Widget _settings({_Account? account}) {
  final store = _Store();
  return MessengerSettingsScreen(
    api: _Api(),
    store: store,
    crypto: _Crypto(),
    accountRepository: account ?? _Account(),
    identityRepository: _Identity(),
    restoreService: _Restore(),
    transferRepository: _Transfer(),
    directoryRepository: null,
    adminRepositoryFactory: _AdminFactory(),
    viewMode: _viewMode,
    adminCapability: AdminCapabilityService(),
    connectivityController: _connectivity,
    notifications: _notifications(store),
    onReset: () async {},
    themeMode: ThemeMode.system,
    onThemeModeChanged: (_) {},
  );
}

Widget _account(_Account repo, AppViewModeCubit viewMode) =>
    AccountCenterScreen(
      accountRepository: repo,
      identityRepository: _Identity(),
      api: _Api(),
      store: _Store(),
      crypto: _Crypto(),
      restoreService: _Restore(),
      transferRepository: _Transfer(),
      directoryRepository: null,
      adminRepositoryFactory: _AdminFactory(),
      viewMode: viewMode,
      adminCapability: AdminCapabilityService(),
      connectivityController: _connectivity,
    );

Widget _people(List<DirectoryProfile> list) {
  final store = _Store();
  final dir = _Directory(list);
  return ContactsScreen(
    directory: dir,
    pairing: PairingService(
        store: store,
        crypto: _Crypto(),
        directory: dir,
        transport: FakePeerTransport()),
    connectivity: _connectivity,
    mesh: MeshBloc(repository: _Mesh()),
    messaging: _Messaging(),
    files: _Files(),
    calls: _calls,
    crypto: _Crypto(),
    notifications: _notifications(store),
    selfUserId: 'me',
  );
}

Widget _callsTab() => CallsScreen(
      controller: CallBloc(
          service: FakeGateway(),
          repository: HistoryRepository()
            ..records.insert(
                0,
                CallRecord(
                  id: 'today-1',
                  callerId: 'self-device',
                  calleeId: 'peer-1',
                  status: 'canceled',
                  startedAt: DateTime.now(),
                  peerName: 'Peer One',
                ))),
      selfId: 'self-device',
      connectivityController: _connectivity,
      onNewCall: () {},
    );

const _people3 = [
  DirectoryProfile(
      userId: 'u-s', deviceId: 'd-s', username: 'sumaira', displayName: 'sumaira'),
  DirectoryProfile(
      userId: 'u-a', deviceId: 'd-a', username: 'ali', displayName: 'ali'),
  DirectoryProfile(userId: 'u-n', username: 'noor', displayName: 'noor'),
];

void _expectTabBar(WidgetTester tester, String title) {
  final bar = find.byType(AppBar);
  expect(bar, findsOneWidget, reason: title);
  expect(find.byType(TabTopBar), findsOneWidget, reason: title);
  expect(find.byType(BackButton), findsNothing, reason: title);
  expect(find.byIcon(Icons.arrow_back), findsNothing, reason: title);
  expect(
      find.descendant(of: bar, matching: find.byType(IconButton)), findsNothing,
      reason: '$title: no icons on the right');
  final text = find.descendant(of: bar, matching: find.text(title));
  expect(text, findsOneWidget, reason: title);
  final at = tester.getTopLeft(text);
  expect(at.dx, 16, reason: '$title starts at 16');
  _titleY[title] = at.dy;
  _titleH[title] = tester.getSize(text).height;
}

final _titleY = <String, double>{};
final _titleH = <String, double>{};

void main() {
  const transport = MethodChannel('locallink/wifi_direct_transport');
  const notifications = MethodChannel('locallink/notifications');
  const actions = MethodChannel('locallink/notification_actions');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    NearbyExperiments.instance.resetForTest();
    PresenceHub.instance.resetForTest();
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(transport, (call) async => null);
    m.setMockMethodCallHandler(notifications, (call) async => null);
    m.setMockMethodCallHandler(actions, (call) async => null);
  });

  tearDown(() {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(transport, null);
    m.setMockMethodCallHandler(notifications, null);
    m.setMockMethodCallHandler(actions, null);
  });

  // ================================================================ T1
  group('T1 the top bar is the same on all 4 tabs', () {
    testWidgets('Settings: no arrow, title at 16, nothing on the right',
        (tester) async {
      await _pushed(tester, _settings());
      _expectTabBar(tester, 'Settings');
    });

    testWidgets('People: "People", no arrow, nothing on the right',
        (tester) async {
      await _pushed(tester, _people(const []));
      await _settle(tester);
      _expectTabBar(tester, 'People');
      expect(find.text('Contacts'), findsNothing);
    });

    testWidgets('Calls: no Wi-Fi icon, no refresh button', (tester) async {
      await _pushed(tester, _callsTab());
      await _settle(tester);
      _expectTabBar(tester, 'Calls');
      expect(find.byTooltip('Refresh calls'), findsNothing);
      expect(find.byIcon(Icons.refresh_rounded), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Chats uses the same bar (with the 5-tap title)',
        (tester) async {
      await _pushed(
          tester,
          Scaffold(
            appBar: TabTopBar(
              title: GestureDetector(
                key: const ValueKey('chats_title_taps'),
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: const Text('Chats'),
              ),
            ),
          ));
      _expectTabBar(tester, 'Chats');
      // All 4 titles: same height on screen and same size (no jump).
      expect(_titleY.length, 4);
      expect(_titleY.values.toSet().length, 1, reason: '$_titleY');
      expect(_titleH.values.toSet().length, 1, reason: '$_titleH');
    });

    test('Chats code: shared bar, 5 taps kept, Wi-Fi icon gone', () {
      final src =
          _src('lib/features/home/presentation/screens/home_screen.dart');
      final chats = src.substring(
          src.indexOf('Widget _chatsTab()'), src.indexOf('Widget _callsTab()'));
      expect(chats.contains('appBar: TabTopBar('), isTrue);
      expect(chats.contains("ValueKey('chats_title_taps')"), isTrue);
      expect(chats.contains('onTap: _onChatsTitleTap'), isTrue);
      expect(src.contains('ConnectionStatusIndicator'), isFalse);
      expect(
          _src('lib/features/calls/presentation/screens/calls_screen.dart')
              .contains('ConnectionStatusIndicator'),
          isFalse);
    });
  });

  // ================================================================ T2
  test('T2 back button on a tab still asks "Press back again to exit"', () {
    final src = _src('lib/features/home/presentation/screens/home_screen.dart');
    expect(src.contains('canPop: false'), isTrue);
    expect(src.contains("Text('Press back again to exit')"), isTrue);
  });

  // ================================================================ T3
  testWidgets('T3 Calls: pull down still reloads, rows unchanged',
      (tester) async {
    await _pushed(tester, _callsTab());
    await _settle(tester);
    expect(find.byType(RefreshIndicator), findsOneWidget);
    expect(
        _src('lib/features/calls/presentation/screens/calls_screen.dart')
            .contains('onRefresh: widget.controller.refreshHistory'),
        isTrue);
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('Today'), findsNothing);
    expect(find.text('Peer One'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });

  // ================================================================ T5
  group('T5 People filter', () {
    Future<void> open(WidgetTester tester) async {
      await _pushed(tester, _people(_people3));
      await _settle(tester);
      PresenceHub.instance.noteNearby('d-s');
      PresenceHub.instance.noteServer('d-a');
      await _settle(tester);
    }

    Future<void> pick(WidgetTester tester, String name) async {
      await tester.tap(find.byKey(const ValueKey('people_filter_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('people_filter_$name')));
      await tester.pumpAndSettle();
    }

    testWidgets('starts at All: everybody, no chip, grey icon',
        (tester) async {
      await open(tester);
      for (final n in ['sumaira', 'ali', 'noor']) {
        expect(find.text(n), findsOneWidget);
      }
      expect(find.byKey(const ValueKey('people_filter_chip')), findsNothing);
      final icon = tester.widget<Icon>(find.byIcon(Icons.tune_outlined));
      expect(icon.color, LocalLinkTheme.light().colorScheme.onSurfaceVariant);
      expect(find.text('YOUR CONTACTS'), findsOneWidget);
    });

    testWidgets('menu: All / Nearby / Online, tick on the chosen one',
        (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('people_filter_button')));
      await tester.pumpAndSettle();
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Nearby'), findsOneWidget);
      expect(find.text('Online'), findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('people_filter_all')),
              matching: find.byIcon(Icons.check)),
          findsOneWidget);
      // Order: All above Nearby above Online.
      expect(tester.getTopLeft(find.text('All')).dy,
          lessThan(tester.getTopLeft(find.text('Nearby')).dy));
      expect(tester.getTopLeft(find.text('Nearby')).dy,
          lessThan(tester.getTopLeft(find.text('Online')).dy));
    });

    testWidgets('Nearby: only nearby people, chip, x = All again',
        (tester) async {
      await open(tester);
      await pick(tester, 'nearby');
      expect(find.text('sumaira'), findsOneWidget);
      expect(find.text('ali'), findsNothing);
      expect(find.text('noor'), findsNothing, reason: 'no phone = Offline');
      expect(find.byKey(const ValueKey('people_filter_chip')), findsOneWidget);
      final icon = tester.widget<Icon>(find.byIcon(Icons.tune_outlined));
      expect(icon.color, LocalLinkTheme.light().colorScheme.primary);
      await tester.tap(find.byKey(const ValueKey('people_filter_clear')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('people_filter_chip')), findsNothing);
      expect(find.text('ali'), findsOneWidget);
      expect(find.text('noor'), findsOneWidget);
    });

    testWidgets('Online: only online people; list follows status live',
        (tester) async {
      await open(tester);
      await pick(tester, 'online');
      expect(find.text('ali'), findsOneWidget);
      expect(find.text('sumaira'), findsNothing);
      // Ali comes nearby -> leaves the Online list by itself.
      PresenceHub.instance.noteNearby('d-a');
      await _settle(tester);
      expect(find.text('ali'), findsNothing);
      expect(find.byKey(const ValueKey('people_filter_empty')), findsOneWidget);
      expect(find.text('No one online right now'), findsOneWidget);
    });

    testWidgets('search and filter work together; empty messages',
        (tester) async {
      await open(tester);
      await pick(tester, 'nearby');
      await tester.enterText(find.byType(TextField), 'sum');
      await tester.pump();
      expect(find.text('sumaira'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'ali');
      await tester.pump();
      expect(find.widgetWithText(ListTile, 'ali'), findsNothing);
      expect(find.text('No people found'), findsOneWidget);
      // Nobody nearby any more (fresh status), search box emptied.
      PresenceHub.instance.resetForTest();
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      expect(find.text('No one nearby right now'), findsOneWidget);
    });

    test('not remembered: always starts at All', () {
      final src =
          _src('lib/features/directory/presentation/contacts_screen.dart');
      expect(src.contains('PeopleFilter _filter = PeopleFilter.all;'), isTrue);
      expect(src.contains('SharedPreferences'), isFalse);
    });
  });

  // ================================================================ F1-F4
  group('196 Settings PRIVACY + People sheets', () {
    setUp(() {
      BlockHub.resetForTest();
      FriendRequestBook.resetForTest();
    });

    testWidgets('PRIVACY sits between THIS PHONE and ADMIN, count shown',
        (tester) async {
      BlockHub.instance.setForTest(
          people: const [BlockedPerson(userId: 'u-ali', name: 'Ali')]);
      await _pushed(tester, _settings());
      await _settle(tester);
      await tester.scrollUntilVisible(find.text('Blocked people'), 100,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('PRIVACY'), findsOneWidget);
      expect(find.text('Private profile'), findsOneWidget);
      expect(find.text('Nobody can find you by name search'), findsOneWidget);
      expect(find.text('See and unblock people you blocked'), findsOneWidget);
      final count = tester.widget<Text>(
          find.byKey(const ValueKey('settings_blocked_count')));
      expect(count.data, '1');
      // Bundle 198: the Read receipts row makes the list longer; a taller
      // screen keeps ADMIN built for the measuring below.
      tester.view.physicalSize = const Size(1080, 3000);
      await tester.pump();
      expect(find.text('Read receipts'), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, 2000));
      await tester.pump();
      final y = (String t) =>
          tester.getTopLeft(find.text(t, skipOffstage: false)).dy;
      expect(y('THIS PHONE'), lessThan(y('PRIVACY')));
      expect(y('PRIVACY'), lessThan(y('ADMIN')));
    });

    testWidgets('Private profile: ON asks first; Cancel keeps it OFF',
        (tester) async {
      final account = _SavingAccount();
      await _pushed(tester, _settings(account: account));
      await _settle(tester);
      final sw = find.byKey(const ValueKey('settings_private_switch'));
      await tester.scrollUntilVisible(sw, 100,
          scrollable: find.byType(Scrollable).first);
      expect(tester.widget<Switch>(sw).value, isFalse);
      await tester.tap(sw);
      await tester.pumpAndSettle();
      expect(find.text('Make your profile private?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('private_profile_cancel')));
      await tester.pumpAndSettle();
      expect(account.savedByName, isEmpty);
      expect(tester.widget<Switch>(sw).value, isFalse);
      await tester.tap(sw);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('private_profile_confirm')));
      await tester.pumpAndSettle();
      expect(account.savedByName, [false]);
      expect(tester.widget<Switch>(sw).value, isTrue);
      expect(find.text('Your profile is private'), findsOneWidget);
      // OFF: no question.
      await tester.tap(sw);
      await tester.pumpAndSettle();
      expect(find.text('Make your profile private?'), findsNothing);
      expect(account.savedByName, [false, true]);
    });

    testWidgets('Blocked people row opens the list', (tester) async {
      await _pushed(tester, _settings());
      await _settle(tester);
      final row = find.byKey(const ValueKey('settings_blocked_people'));
      await tester.scrollUntilVisible(row, 100,
          scrollable: find.byType(Scrollable).first);
      // Bundle 197b: the new Storage row pushes it lower - fully on screen.
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(find.text("You haven't blocked anyone."), findsOneWidget);
    });

    testWidgets('People: ⋮ = actions sheet; Private label; no pop-up',
        (tester) async {
      await _pushed(
          tester,
          _people(const [
            DirectoryProfile(
                userId: 'u-s',
                deviceId: 'd-s',
                username: 'sumaira',
                displayName: 'sumaira',
                discoverableByName: false),
            DirectoryProfile(
                userId: 'u-a', deviceId: 'd-a', username: 'ali', displayName: 'ali'),
          ]));
      await _settle(tester);
      expect(find.byKey(const ValueKey('people_private_u-s')), findsOneWidget);
      expect(find.byKey(const ValueKey('people_private_u-a')), findsNothing);
      expect(find.byType(PopupMenuButton<String>), findsNothing);
      await tester.tap(find.byKey(const ValueKey('people_more_u-a')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('contact_actions_sheet')), findsOneWidget);
      expect(find.text('Block ali'), findsOneWidget);
      await tester.tap(find.text('Block ali'));
      await tester.pumpAndSettle();
      expect(find.text('Block ali?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('block_sheet_cancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('block_sheet')), findsNothing);
    });

    testWidgets('People: REQUESTS on top, red BLOCKED at the bottom (All only)',
        (tester) async {
      BlockHub.instance.setForTest(people: const [
        BlockedPerson(userId: 'u-ali', name: 'Ali', username: 'ali'),
      ]);
      FriendRequestBook.instance.now = () => 1060000;
      await FriendRequestBook.instance.addIncoming(const FriendRequest(
          deviceId: 'd-k',
          userId: 'u-k',
          name: 'Kamran',
          username: 'kamran',
          atMs: 1000000,
          body: '{}'));
      await _pushed(tester, _people(_people3));
      await _settle(tester);
      expect(find.text('REQUESTS'), findsOneWidget);
      expect(find.text('@kamran · wants to add you · 1 min'), findsOneWidget);
      expect(find.byKey(const ValueKey('request_accept_d-k')), findsOneWidget);
      expect(find.byKey(const ValueKey('request_decline_d-k')), findsOneWidget);
      final y = (String t) =>
          tester.getTopLeft(find.text(t, skipOffstage: false)).dy;
      expect(y('REQUESTS'), lessThan(y('YOUR CONTACTS')));
      await tester.scrollUntilVisible(find.text('BLOCKED'), 100,
          scrollable: find.byType(Scrollable).first);
      expect(y('YOUR CONTACTS'), lessThan(y('BLOCKED')));
      final label = tester.widget<Text>(find.text('BLOCKED'));
      expect(label.style?.color, LocalLinkTheme.light().colorScheme.error);
      expect(find.byType(BlockedPill), findsOneWidget);
      // Decline: the row goes, nothing else happens.
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('request_decline_d-k')), -100,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.byKey(const ValueKey('request_decline_d-k')));
      await _settle(tester);
      expect(find.text('REQUESTS'), findsNothing);
    });
  });

  group('F Settings', () {
    testWidgets('one way into Account, plain card line, sections in order',
        (tester) async {
      await _pushed(tester, _settings());
      expect(find.text('Account & profile'), findsNothing);
      expect(find.text('Privacy & security'), findsNothing);
      expect(find.text('My LinkUp phone · Account and profile'), findsNothing);
      expect(find.textContaining('My LinkUp phone'), findsNothing);
      expect(find.text('@sajjad · Account, phones, backup'), findsOneWidget);
      final order = [
        'GENERAL',
        'Notifications',
        'Appearance',
        'THIS PHONE',
        'Keep LinkUp running',
        'Reset setup',
        'ADMIN',
        'Admin panel',
      ];
      for (final t in order) {
        await tester.scrollUntilVisible(find.text(t), 100,
            scrollable: find.byType(Scrollable).first);
      }
      // Bundle 198: the Read receipts row makes the list longer; a taller
      // screen keeps the whole list built for the measuring below.
      tester.view.physicalSize = const Size(1080, 3000);
      await tester.pump();
      await tester.drag(find.byType(ListView), const Offset(0, 2000));
      await tester.pump();
      double? last;
      for (final t in order) {
        final y = tester.getTopLeft(find.text(t, skipOffstage: false)).dy;
        if (last != null) expect(y, greaterThan(last), reason: t);
        last = y;
      }
      expect(find.text('Messages, groups and calls'), findsOneWidget);
      expect(find.text('Get messages and calls when closed'), findsOneWidget);
      expect(find.text('Start again on this phone'), findsOneWidget);
      expect(find.text('Tools for testing', skipOffstage: false),
          findsOneWidget);
    });

    testWidgets('sizes: card 16 from the edge, title 6 inside, row 72',
        (tester) async {
      await _pushed(tester, _settings());
      final card = find.byKey(const ValueKey('settings_profile_card'));
      expect(tester.getTopLeft(card).dx, 16);
      expect(tester.getSize(card).height, 88);
      expect(tester.getTopLeft(find.text('GENERAL')).dx, 22);
      // (Appearance: its small line fits on one line with the test font;
      // the test font is wider than Roboto.)
      final row = find.ancestor(
          of: find.text('Appearance'), matching: find.byType(ListTile));
      expect(tester.getSize(row).height, 72);
      expect(tester.getTopLeft(find.text('Notifications')).dx, 16 + 72);
      final label = tester.widget<Text>(find.text('GENERAL'));
      expect(label.style!.fontSize, 11);
      expect(label.style!.letterSpacing, 1.1);
    });

    testWidgets('the top card opens Account', (tester) async {
      await _pushed(tester, _settings());
      await tester.tap(find.byKey(const ValueKey('settings_profile_card')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await _settle(tester);
      expect(find.byType(AccountCenterScreen), findsOneWidget);
    });

    test('no tech words or old name on Settings', () {
      final src = _src(
          'lib/features/home/presentation/screens/messenger_settings_screen.dart');
      for (final w in [
        'Local link',
        'Wi-Fi Direct',
        'mesh)',
        'battery exemption',
        "'Account & profile'",
        "'Privacy & security'",
        'AppBar(',
      ]) {
        expect(src.contains(w), isFalse, reason: w);
      }
      expect(src.contains('_openAccount(context)'), isTrue);
      expect('_openAccount(context)'.allMatches(src).length, 1);
    });
  });

  // ================================================================ F5-F9
  group('F Account', () {
    testWidgets('profile card, sections in order, plain words',
        (tester) async {
      await _pushed(tester, _account(_Account(), AppViewModeCubit()));
      await _settle(tester);
      expect(find.text('My profile'), findsNothing);
      expect(find.text('Tap to edit name and photo'), findsOneWidget);
      expect(find.byKey(const ValueKey('account_profile_edit')), findsOneWidget);
      expect(tester.getSize(find.byKey(const ValueKey('account_profile_card'))).height,
          104);
      final order = [
        'PHONES',
        'My phones',
        'Move to a new phone',
        'BACKUP AND SAFETY',
        'Backup and restore',
        'Security key',
        'Extra nearby safety',
        'Keep your recovery code private',
      ];
      double? last;
      for (final t in order) {
        final f = find.text(t, skipOffstage: false);
        expect(f, findsOneWidget, reason: t);
        final y = tester.getTopLeft(f).dy;
        if (last != null) expect(y, greaterThan(last), reason: t);
        last = y;
      }
      for (final old in [
        'Trusted devices',
        'Transfer account',
        'Account data',
        'Identity key',
        'Data & security',
      ]) {
        expect(find.text(old, skipOffstage: false), findsNothing, reason: old);
      }
      expect(find.text('Only contacts the app can confirm', skipOffstage: false),
          findsOneWidget);
      // Account keeps its back arrow (it is opened from Settings).
      expect(find.byType(BackButton), findsOneWidget);
    });

    testWidgets('the card opens the profile screen', (tester) async {
      final src = _src(
          'lib/features/account/presentation/screens/account_center_screen.dart');
      expect(src.contains("ValueKey('account_profile_card'),\n                          onTap: _openProfile"), isTrue);
      expect('_openProfile'.allMatches(src).length, 2); // definition + card
    });

    test('each row still opens the same screen as before', () {
      final src = _src(
          'lib/features/account/presentation/screens/account_center_screen.dart');
      for (final s in [
        'builder: (_) => DevicesScreen(',
        'builder: (_) => AccountTransferScreen(',
        'builder: (_) => AccountRestoreScreen(',
        'builder: (_) => CryptoMigrationScreen(',
        'const ExtraNearbySafetySwitch()',
      ]) {
        expect(src.contains(s), isTrue, reason: s);
      }
    });

    testWidgets('extra nearby safety still asks before turning on',
        (tester) async {
      await _pushed(tester, _account(_Account(), AppViewModeCubit()));
      await _settle(tester);
      final sw = find.byKey(const Key('nearby_strict_link_check'));
      await tester.scrollUntilVisible(sw, 100,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(sw);
      await tester.pumpAndSettle();
      expect(find.text('Turn on extra nearby safety?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(NearbyExperiments.instance.strictLinkCheck, isFalse);
    });

    testWidgets('offline box: new words, follows the live status by itself',
        (tester) async {
      final repo = _Account()..error = Exception('timeout');
      final view = AppViewModeCubit(); // not connected
      await _pushed(tester, _account(repo, view));
      await _settle(tester);
      expect(find.byKey(const ValueKey('account_offline_box')), findsOneWidget);
      expect(find.text("Can't reach LinkUp. Showing saved profile."),
          findsOneWidget);
      expect(find.textContaining('server'), findsNothing);
      // LinkUp comes back while the screen is open -> box goes away.
      repo.error = null;
      view.setServerConnected(true);
      await _settle(tester);
      await _settle(tester);
      expect(find.byKey(const ValueKey('account_offline_box')), findsNothing);
      expect(repo.loads, greaterThanOrEqualTo(2));
    });

    testWidgets('connected: no offline box', (tester) async {
      final view = AppViewModeCubit()..setServerConnected(true);
      await _pushed(tester, _account(_Account(), view));
      await _settle(tester);
      expect(find.byKey(const ValueKey('account_offline_box')), findsNothing);
    });
  });

  // ================================================================ F10
  test('F10 titles of the screens that open match the rows', () {
    expect(
        _src('lib/features/account/presentation/screens/devices_screen.dart')
            .contains("title: const Text('My phones')"),
        isTrue);
    expect(
        _src('lib/features/account/presentation/screens/devices_screen.dart')
            .contains("title: const Text('Remove this phone?')"),
        isTrue);
    expect(
        _src('lib/features/transfer/presentation/screens/account_transfer_screen.dart')
            .contains("title: const Text('Move to a new phone')"),
        isTrue);
    expect(
        _src('lib/features/recovery/presentation/screens/account_restore_screen.dart')
            .contains("title: const Text('Backup and restore')"),
        isTrue);
    final key = _src(
        'lib/features/account/presentation/screens/crypto_migration_screen.dart');
    expect(key.contains("title: const Text('Security key')"), isTrue);
    expect(key.contains("title: const Text('Change security key?')"), isTrue);
  });

  // ================================================================ T6
  group('T6 one style: shared title and card everywhere', () {
    test('every screen uses the shared pieces, no own copies', () {
      final files = {
        'chats': 'lib/features/home/presentation/screens/home_screen.dart',
        'calls': 'lib/features/calls/presentation/screens/calls_screen.dart',
        'people': 'lib/features/directory/presentation/contacts_screen.dart',
        'settings':
            'lib/features/home/presentation/screens/messenger_settings_screen.dart',
        'account':
            'lib/features/account/presentation/screens/account_center_screen.dart',
      };
      files.forEach((name, path) {
        final s = _src(path);
        expect(s.contains('MessengerGroupLabel('), isTrue, reason: name);
        expect(s.contains('MessengerListGroup('), isTrue, reason: name);
        expect(s.contains('MessengerSectionHeader'), isFalse, reason: name);
        expect(s.contains('Widget _sectionLabel'), isFalse, reason: name);
        expect(s.contains('Widget _group('), isFalse, reason: name);
      });
    });

    testWidgets('title = small grey CAPITALS; card = Settings grey',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: LocalLinkTheme.light(),
        home: const Scaffold(
          body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            MessengerGroupLabel('Conversations'),
            MessengerListGroup(children: [
              SizedBox(height: 40),
              SizedBox(height: 40),
            ]),
          ]),
        ),
      ));
      final scheme = LocalLinkTheme.light().colorScheme;
      final text = tester.widget<Text>(find.text('CONVERSATIONS'));
      expect(text.style!.fontSize, 11);
      expect(text.style!.letterSpacing, 1.1);
      expect(text.style!.color, scheme.onSurfaceVariant);
      final material = tester.widget<Material>(find
          .descendant(
              of: find.byType(MessengerListGroup),
              matching: find.byType(Material))
          .first);
      expect(material.color, scheme.surfaceContainer.withValues(alpha: .65));
      final shape = material.shape! as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(20));
      expect(shape.side.color, scheme.outlineVariant.withValues(alpha: .35));
      final divider = tester.widget<Divider>(find.byType(Divider));
      expect(divider.color, scheme.outlineVariant.withValues(alpha: .4));
      expect(divider.indent, 72);
      expect(tester.getTopLeft(find.text('CONVERSATIONS')).dx, 22);
    });
  });

  // ================================================================ T7
  test('T7 status dot widget untouched', () {
    final src = _src('lib/core/widgets/messenger_conversation_tile.dart');
    expect(src.contains('class PresenceAvatar'), isTrue);
    expect(src.contains('width: 14,'), isTrue);
    expect(src.contains("'nearby' => (colors.primary, Icons.wifi_rounded),"),
        isTrue);
  });
}

