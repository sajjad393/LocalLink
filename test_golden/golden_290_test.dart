// 3.0.90 look check (PLAN_3.0.90 Phase 2.7 / 8): renders the new screens
// with the real Roboto + Material icon fonts so they can be put next to the
// mocks (compare_3.0.90.html). Not part of the normal suite (fonts differ by
// machine), run by hand:
//   flutter test --update-goldens test_golden/golden_290_test.dart
//   GOLDEN_ALL=1 ... = all 12 sizes/modes (3 sizes x dark/light x text 1.0/1.3)
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/account.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/theme/app_theme.dart';
import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/core/widgets/link_kit_290.dart' show LinkKit;
import 'package:locallink/core/widgets/link_toast.dart';
import 'package:locallink/features/account/domain/account_repository_contract.dart';
import 'package:locallink/features/account/presentation/widgets/photo_save_ring284.dart';
import 'package:locallink/features/authentication/data/models/authentication_models.dart';
import 'package:locallink/features/authentication/domain/authentication_repository_contract.dart';
import 'package:locallink/features/authentication/presentation/screens/setup_screen.dart';
import 'package:locallink/features/authentication/presentation/screens/welcome_screen.dart';
import 'package:locallink/core/models/call.dart';
import 'package:locallink/features/calls/presentation/widgets/call_history_tile.dart';
import 'package:locallink/features/directory/data/people_to_add_267.dart';
import 'package:locallink/features/directory/domain/directory_models.dart';
import 'package:locallink/features/directory/presentation/add_contact_screen.dart';
import 'package:locallink/features/directory/presentation/add_contact_ui283.dart';
import 'package:locallink/features/recovery/domain/account_restoration_repository_contract.dart';
import 'package:locallink/features/recovery/domain/recovery_repository_contract.dart';
import 'package:locallink/features/recovery/presentation/screens/account_recovery_screen.dart';
import 'package:locallink/features/recovery/presentation/screens/recovery_code_286.dart';
import 'package:locallink/features/transfer/domain/account_transfer_repository_contract.dart';

import '../test/support/g211_fakes.dart';

const _code = 'K7QM2-XPA9T-RC4WN-E8D3F';

class _Store extends Store211 {
  final settings = <String, String>{};
  @override
  String? get username => 'sajjad';
  @override
  String? get localRecoveryCode => _code;
  @override
  Future<String?> readSetting(String key) async => settings[key];
  @override
  Future<void> writeSetting(String key, String value) async => settings[key] = value;
}

class _NoSuch {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Accounts extends _NoSuch implements AccountRepositoryContract {}

class _Recovery extends _NoSuch implements RecoveryRepositoryContract {
  @override
  Future<bool> serverOnline222() async => true;
  @override
  Future<Map<String, String>?> pendingRequest() async => null;
  @override
  String? get serverAddress => 'http://10.0.0.2:8080';
  @override
  Future<AuthResult> resetWithCode222(
          {required String username, required String recoveryCode, required String newPassword}) async =>
      AuthResult(
        account: LocalAccount.fromJson({'id': 'u1', 'username': username}),
        device: Device.fromJson({'id': 'd1', 'name': 'ZTE'}),
        expiresAt: '',
        recoveryCode: _code,
      );
}

class _Transfer extends _NoSuch implements AccountTransferRepositoryContract {}

class _Restore extends _NoSuch implements AccountRestorationRepositoryContract {}

class _Auth extends _NoSuch implements AuthenticationRepositoryContract {
  @override
  String generateUniqueDeviceName() => 'phone-290';
}

Future<void> _loadFonts() async {
  Future<void> family(String name, List<String> paths) async {
    final loader = FontLoader(name);
    for (final p in paths) {
      loader.addFont(Future.value(ByteData.sublistView(File(p).readAsBytesSync())));
    }
    await loader.load();
  }

  await family(LocalLinkLook.fontFamily, [
    'assets/fonts/Roboto-Regular.ttf',
    'assets/fonts/Roboto-Medium.ttf',
    'assets/fonts/Roboto-SemiBold.ttf',
    'assets/fonts/Roboto-Bold.ttf',
  ]);
  final root = Platform.environment['FLUTTER_ROOT'] ?? '';
  final icons = '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf';
  if (File(icons).existsSync()) await family('MaterialIcons', [icons]);
  // The app asks Android for the system 'monospace' font (codes). Tests have no
  // system fonts, so load any mono font under that name when one is on this PC.
  const monoPaths = [
    '/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf',
  ];
  final mono = monoPaths.where((p) => File(p).existsSync()).toList();
  if (mono.isNotEmpty) await family(LinkKit.mono, mono);
}

typedef _Mode = ({Size size, bool dark, double text});

List<_Mode> _modes() {
  if (Platform.environment['GOLDEN_ALL'] != '1') {
    return [
      (size: const Size(360, 800), dark: true, text: 1.0),
      (size: const Size(360, 800), dark: false, text: 1.0),
    ];
  }
  return [
    for (final s in const [Size(320, 640), Size(360, 800), Size(412, 915)])
      for (final d in const [true, false])
        for (final t in const [1.0, 1.3]) (size: s, dark: d, text: t),
  ];
}

String _tag(_Mode m) =>
    '${m.size.width.toInt()}x${m.size.height.toInt()}_${m.dark ? 'dark' : 'light'}_${m.text == 1 ? '10' : '13'}';

Widget _app(_Mode m, Widget home) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: LocalLinkTheme.light(),
      darkTheme: LocalLinkTheme.dark(),
      themeMode: m.dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) => MediaQuery(
        data: LocalLinkLook.clampScaler(MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(m.text))),
        child: child!,
      ),
      home: home,
    );

Widget _page(String title, Widget body) => Builder(
      builder: (context) => Scaffold(
        appBar: addBar283(context, title: title),
        body: SingleChildScrollView(padding: const EdgeInsets.symmetric(horizontal: 16), child: body),
      ),
    );

const _sara = DirectoryProfile(userId: 'u-a', username: 'ayesha', displayName: 'ayesha', deviceId: '');
const _khan = DirectoryProfile(userId: 'u-b', username: 'ayesha.k', displayName: 'Ayesha Khan', deviceId: '');

CallRecord _call(String id, String status, int h) => CallRecord(
      id: id,
      callerId: status == 'missed' ? 'd-n' : 'me',
      calleeId: status == 'missed' ? 'me' : 'd-n',
      status: status,
      startedAt: DateTime(2026, 11, 13, h),
      peerName: 'noshad',
    );

final Map<String, Widget Function()> _screens = {
  // 288
  '288_welcome': () => WelcomeScreen(
        api: Api211(),
        authentication: _Auth(),
        store: Store211(),
        accountRepository: _Accounts(),
        onSaved: () async {},
        recoveryRepository: _Recovery(),
        transferRepository: _Transfer(),
        restorationService: _Restore(),
      ),
  '288_login': () => SetupScreen(
        authentication: _Auth(),
        accountRepository: _Accounts(),
        store: Store211(),
        api: Api211(),
        onSaved: () async {},
        recoveryRepository: _Recovery(),
        transferRepository: _Transfer(),
        restorationService: _Restore(),
      ),
  '288_create': () => SetupScreen(
        authentication: _Auth(),
        accountRepository: _Accounts(),
        store: Store211(),
        api: Api211(),
        onSaved: () async {},
        recoveryRepository: _Recovery(),
        transferRepository: _Transfer(),
        restorationService: _Restore(),
        initialRegisterMode: true,
      ),
  // 287
  '287_forgot': () =>
      ForgotPasswordScreen222(repository: _Recovery(), onCompleted: () async {}, initialUsername: 'sajjad'),
  // 286
  '286_card_new': () {
    final s = _Store()..settings['recovery_new_286:sajjad'] = '1';
    return _page('Chats', Column(children: [RecoveryHomeCard286(store: s, accounts: _Accounts())]));
  },
  '286_card_existing': () =>
      _page('Chats', Column(children: [RecoveryHomeCard286(store: _Store(), accounts: _Accounts())])),
  '286_password': () => RecoveryPasswordScreen286(store: _Store(), accounts: _Accounts()),
  '286_code': () => RecoveryCodeScreen286(store: _Store(), accounts: _Accounts(), code: _code),
  '286_row': () => _page('Account', RecoveryRow286(store: _Store(), accounts: _Accounts())),
  // 285
  '285_calls': () => _page(
        'Calls',
        Column(children: [
          CallHistoryTile(
            call: _call('c1', 'completed', 21),
            title: 'noshad',
            status: 'Outgoing',
            date: '9:00 PM',
            duration: '2:14',
            selfId: 'me',
            count: 9,
            missedInside: 3,
            onCall: () {},
            onOpen: () {},
          ),
          CallHistoryTile(
            call: _call('c2', 'missed', 20),
            title: 'Ibrahim',
            status: 'Missed',
            date: '8:00 PM',
            duration: null,
            selfId: 'me',
            missed: true,
            count: 4,
            onCall: () {},
            onOpen: () {},
          ),
        ]),
      ),
  // 284
  '284_photo_ring': () => _page(
        'Profile',
        Center(
          child: Padding(
            padding: const EdgeInsets.only(top: 24),
            child: PhotoSaveRing284(
              saving: true,
              done: false,
              radius: 52,
              child: CircleAvatar(radius: 52, backgroundColor: LocalLinkAvatarColor.forName('sajjad'), child: const Text('S')),
            ),
          ),
        ),
      ),
  // 289
  '289_toasts': () => Builder(builder: (context) {
        WidgetsBinding.instance.addPostFrameCallback(
            (_) => LinkToast.show(context, 'Recovery code saved', kind: LinkToastKind.done));
        return _page('Chats', const SizedBox(height: 400));
      }),
  // 283
  '283_empty': () => _page(
        'Add Contact',
        EmptyAdd283(
          title: PeopleToAdd267.emptyServerTitle,
          text: PeopleToAdd267.emptyServer,
          onMyQr: () {},
          onNearby: () {},
        ),
      ),
  '283_results': () => _page(
        'Add Contact',
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SectionTitle283('Results'),
          SearchResultCard(profile: _sara, initial: 'A', isContact: true, onOpen: () {}, onAdd: () {}),
          SearchResultCard(profile: _khan, initial: 'A', isContact: false, onOpen: () {}, onAdd: () {}),
        ]),
      ),
  '283_not_found': () => _page(
        'Add Contact',
        const Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          NotFoundCard283(query: 'sa'),
          SectionTitle283('People nearby', live: true),
          QuietLine283('Everyone nearby is already in your contacts'),
          QrHint283(),
        ]),
      ),
  '283_looking': () => _page(
        'Add Contact',
        const Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SectionTitle283('People nearby', live: true),
          NearbyScene283(meInitial: 'S'),
          SizedBox(height: 14),
          LookingText283('Looking for phones near you'),
        ]),
      ),
  '283_found': () => _page(
        'Add Contact',
        const Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SectionTitle283('People nearby', live: true),
          NearbyScene283(meInitial: 'S', found: 1, foundInitial: 'Z'),
        ]),
      ),
  '283_cards': () => _page(
        'Add Contact',
        const Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SectionTitle283('People nearby'),
          WarnCard283(
              kind: WarnKind283.wifi,
              title: 'Wi-Fi is off',
              text: 'Turn it on to find phones near you',
              action: 'Turn on'),
          WarnCard283(
              kind: WarnKind283.nearby,
              title: 'Find phones near you',
              text: 'LinkUp needs your OK once',
              action: 'Allow'),
          SizedBox(height: 20),
          ScanButton283(),
        ]),
      ),
};

void main() {
  setUpAll(_loadFonts);

  for (final m in _modes()) {
    for (final e in _screens.entries) {
      testWidgets('${e.key} ${_tag(m)}', (tester) async {
        tester.view.physicalSize = m.size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_app(m, e.value()));
        for (var i = 0; i < 14; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 100));
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/${e.key}_${_tag(m)}.png'));
        // Stop endless tickers before the test ends.
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 5));
      });
    }
  }
}
