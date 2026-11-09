// Bundle 222: Forgot password (code + new password online / no server) and
// the no-code request to the admin. Mocks R-1 … R-5.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/account.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/features/authentication/data/models/authentication_models.dart';
import 'package:locallink/features/recovery/bloc/account_recovery_bloc.dart' show ForgotPasswordBloc222, ForgotTab222;
import 'package:locallink/features/recovery/domain/recovery_repository_contract.dart';
import 'package:locallink/features/recovery/presentation/screens/account_recovery_screen.dart';
import 'package:locallink/features/recovery/presentation/widgets/recovery_code_save_235.dart';

class _Repo implements RecoveryRepositoryContract {
  bool online = true;
  Object? resetError;
  Object? offlineError;
  int onlineCalls = 0, offlineCalls = 0, completeCalls = 0;
  String lastCode = '', lastPassword = '', lastOneTime = '';
  Map<String, String>? saved;
  String status = 'pending';

  @override
  Future<bool> serverOnline222() async => online;

  @override
  Future<AuthResult> resetWithCode222({required String username, required String recoveryCode, required String newPassword}) async {
    onlineCalls++;
    lastCode = recoveryCode;
    lastPassword = newPassword;
    if (resetError != null) throw resetError!;
    return AuthResult(
      account: LocalAccount.fromJson({'id': 'u1', 'username': username}),
      device: Device.fromJson({'id': 'd1', 'name': 'ZTE'}),
      expiresAt: '',
      recoveryCode: 'P3HD8-LKWT6-MZQA2-RX7YB',
    );
  }

  @override
  String? offlineResetProblem222({required String username, required String recoveryCode}) => null;

  @override
  Future<void> resetOffline222({required String username, required String recoveryCode, required String newPassword}) async {
    offlineCalls++;
    if (offlineError != null) throw offlineError!;
  }

  @override
  Future<({AccountRecoveryStart start, String server})> createNoCodeRequest222({required String username}) async {
    saved = {'request_id': 'req-123456789', 'request_secret': 'sec'};
    return (
      start: AccountRecoveryStart.fromJson({'request': {'request_id': 'req-123456789', 'status': 'pending', 'username': username}, 'request_secret': 'sec'}),
      server: 'http://10.0.0.2:8080',
    );
  }

  @override
  Future<String> completeNoCode222({required String server, required String requestId, required String requestSecret, required String oneTimeCode, required String newPassword}) async {
    completeCalls++;
    lastOneTime = oneTimeCode;
    return 'NEW22-CODE2-FROMA-DMIN2';
  }

  @override
  Future<AccountRecoveryState> recoveryStatus({required String server, required String requestId, required String requestSecret}) async =>
      AccountRecoveryState.fromJson({'request_id': requestId, 'status': status, 'username': 'sajjad'});

  @override
  Future<Map<String, String>?> pendingRequest() async => saved;

  @override
  Future<void> clearPendingRequest() async => saved = null;

  @override
  String? get serverAddress => 'http://10.0.0.2:8080';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _code = 'K7QM2-XPA9T-RC4WN-E8D3F';

void main() {
  group('bloc', () {
    test('code + new password online: done at once with the new code', () async {
      final repo = _Repo();
      final bloc = ForgotPasswordBloc222(repo);
      await bloc.start();
      expect(bloc.state.online, isTrue);
      await bloc.resetWithCode(username: ' Sajjad ', recoveryCode: 'k7qm2 xpa9t rc4wn e8d3f', newPassword: 'new-pass-1', again: 'new-pass-1');
      expect(repo.onlineCalls, 1);
      expect(repo.offlineCalls, 0);
      expect(bloc.state.doneCode, 'P3HD8-LKWT6-MZQA2-RX7YB');
      expect(bloc.state.doneOffline, isFalse);
      await bloc.close();
    });

    test('checks before sending: name, code, length, same twice', () async {
      final repo = _Repo();
      final bloc = ForgotPasswordBloc222(repo);
      await bloc.start();
      await bloc.resetWithCode(username: '', recoveryCode: _code, newPassword: 'new-pass-1', again: 'new-pass-1');
      expect(bloc.state.error, 'Enter your username.');
      await bloc.resetWithCode(username: 'sajjad', recoveryCode: 'K7QM-2XPA', newPassword: 'new-pass-1', again: 'new-pass-1');
      expect(bloc.state.error, startsWith('Enter your recovery code'));
      await bloc.resetWithCode(username: 'sajjad', recoveryCode: _code, newPassword: 'short', again: 'short');
      expect(bloc.state.error, 'Password must be at least 8 characters.');
      await bloc.resetWithCode(username: 'sajjad', recoveryCode: _code, newPassword: 'new-pass-1', again: 'new-pass-2');
      expect(bloc.state.error, 'The two passwords are not the same.');
      await bloc.resetWithCode(username: 'sajjad', recoveryCode: _code, newPassword: 'new\u0001pass-1', again: 'new\u0001pass-1');
      expect(bloc.state.error, contains('not allowed'));
      expect(repo.onlineCalls, 0);
      await bloc.close();
    });

    test('server answers become plain words', () async {
      final cases = {
        const ApiError218('x', code: 'BAD_RECOVERY_CODE', status: 401): 'Username or recovery code is wrong.',
        const ApiError218('x', code: 'RATE_LIMIT', status: 429): 'Too many tries. Try again in 1 minute.',
        const ApiError218('x', code: 'NOT_ACTIVE', status: 403): 'This account is not active. Ask the admin.',
        const ApiError218('x', code: 'NO_ACCOUNT', status: 404): 'No account with this username.',
        const ResetProblem222('not_last'): 'Without the server this works only for the last account on this phone.',
        const ResetProblem222('bad_code'): 'Username or recovery code is wrong.',
      };
      for (final entry in cases.entries) {
        expect(ForgotPasswordBloc222.textFor222(entry.key), entry.value);
      }
      final repo = _Repo()..resetError = const ApiError218('x', code: 'RATE_LIMIT', status: 429);
      final bloc = ForgotPasswordBloc222(repo);
      await bloc.start();
      await bloc.resetWithCode(username: 'sajjad', recoveryCode: _code, newPassword: 'new-pass-1', again: 'new-pass-1');
      expect(bloc.state.error, 'Too many tries. Try again in 1 minute.');
      expect(bloc.state.doneCode, isNull);
      await bloc.close();
    });

    test('no server: the same phone path, done with no code yet', () async {
      final repo = _Repo()..online = false;
      final bloc = ForgotPasswordBloc222(repo);
      await bloc.start();
      await bloc.resetWithCode(username: 'sajjad', recoveryCode: _code, newPassword: 'new-pass-1', again: 'new-pass-1');
      expect(repo.offlineCalls, 1);
      expect(repo.onlineCalls, 0);
      expect(bloc.state.doneCode, '');
      expect(bloc.state.doneOffline, isTrue);
      await bloc.close();
    });

    test('server gone between check and send: no crash, chip turns orange', () async {
      final repo = _Repo()..resetError = const SocketException('Connection refused');
      final bloc = ForgotPasswordBloc222(repo);
      await bloc.start();
      await bloc.resetWithCode(username: 'sajjad', recoveryCode: _code, newPassword: 'new-pass-1', again: 'new-pass-1');
      expect(bloc.state.online, isFalse);
      expect(bloc.state.error, 'Could not reach the server. Try again.');
      await bloc.close();
    });

    test('no code: ask the admin, wait (no time limit), one-time code + new password', () async {
      final repo = _Repo();
      final bloc = ForgotPasswordBloc222(repo);
      await bloc.start();
      bloc.selectTab(ForgotTab222.noCode);
      await bloc.askAdmin(username: 'sajjad');
      expect(bloc.state.hasRequest, isTrue);
      expect(bloc.state.requestStatus, 'pending');
      expect(ForgotPasswordBloc222.pollEvery, const Duration(seconds: 30));
      await bloc.completeNoCode(oneTimeCode: '1234-5678', newPassword: 'new-pass-1', again: 'new-pass-1');
      expect(bloc.state.error, 'Enter the 12-digit code from the admin.');
      repo.status = 'approved';
      await bloc.pollOnce();
      expect(bloc.state.requestStatus, 'approved');
      await bloc.completeNoCode(oneTimeCode: '1234-5678-9012', newPassword: 'new-pass-1', again: 'new-pass-1');
      expect(repo.lastOneTime, '123456789012');
      expect(bloc.state.doneCode, 'NEW22-CODE2-FROMA-DMIN2');
      await bloc.close();
    });

    test('a saved request comes back after an app restart', () async {
      final repo = _Repo()..saved = {'request_id': 'req-1', 'request_secret': 's'};
      final bloc = ForgotPasswordBloc222(repo);
      await bloc.start();
      expect(bloc.state.tab, ForgotTab222.noCode);
      expect(bloc.state.hasRequest, isTrue);
      await bloc.cancelRequest();
      expect(bloc.state.hasRequest, isFalse);
      expect(repo.saved, isNull);
      await bloc.close();
    });

    test('no code needs the server', () async {
      final repo = _Repo()..online = false;
      final bloc = ForgotPasswordBloc222(repo);
      await bloc.start();
      await bloc.askAdmin(username: 'sajjad');
      expect(bloc.state.error, 'This needs the server. Try again when the server is back.');
      expect(repo.saved, isNull);
      await bloc.close();
    });
  });

  group('screen', () {
    Future<void> pump(WidgetTester tester, _Repo repo, {Future<void> Function()? done}) async {
      await tester.pumpWidget(MaterialApp(
        home: ForgotPasswordScreen222(repository: repo, onCompleted: done ?? () async {}, initialUsername: 'sajjad'),
      ));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('R-2: chip, tabs, fields, OK when typed the same', (tester) async {
      await pump(tester, _Repo());
      expect(find.text('Forgot password'), findsOneWidget);
      expect(find.text('Server connected'), findsOneWidget);
      expect(find.text('I have my recovery code'), findsOneWidget);
      expect(find.text("I don't have it"), findsOneWidget);
      for (final label in ['Username', 'Recovery code', 'New password', 'New password again']) {
        expect(find.text(label), findsWidgets);
      }
      expect(find.text('Set new password'), findsOneWidget);
      expect(find.text('Your other phones stay signed in. You get a new recovery code after this.'), findsOneWidget);
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(2), 'new-pass-1');
      await tester.enterText(fields.at(3), 'new-pass-1');
      await tester.pump();
      expect(find.byKey(const ValueKey('forgot222-same')), findsOneWidget);
    });

    testWidgets('R-3: no server chip and note', (tester) async {
      await pump(tester, _Repo()..online = false);
      expect(find.text('No server \u00b7 works on this phone only'), findsOneWidget);
      expect(find.text('Uses the code saved on this phone. The new password goes to the server when it is back.'), findsOneWidget);
    });

    testWidgets('R-4: new code shown once (hidden, Show), Copy, Share, Save on WhatsApp', (tester) async {
      // Bundle 235 addition: the code starts hidden; "I saved it" became
      // "Save on WhatsApp" (closes when the app is back from WhatsApp).
      WhatsAppShare235.debugOpen = (text) async => true;
      addTearDown(() => WhatsAppShare235.debugOpen = null);
      var finished = 0;
      await pump(tester, _Repo(), done: () async => finished++);
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(1), _code);
      await tester.enterText(fields.at(2), 'new-pass-1');
      await tester.enterText(fields.at(3), 'new-pass-1');
      await tester.tap(find.text('Set new password'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Password changed'), findsOneWidget);
      expect(find.text("You're signed in"), findsOneWidget);
      expect(find.text('P3HD8-LKWT6-MZQA2-RX7YB'), findsNothing);
      await tester.tap(find.text('Show'));
      await tester.pump();
      expect(find.text('P3HD8-LKWT6-MZQA2-RX7YB'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      await tester.tap(find.text('Save on WhatsApp'));
      await tester.pump();
      expect(finished, 0);
      for (final s in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused,
          AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
        tester.binding.handleAppLifecycleStateChanged(s);
      }
      await tester.pump();
      await tester.pump();
      expect(finished, 1);
    });

    testWidgets('R-5: waiting card with one-time code and Cancel request', (tester) async {
      final repo = _Repo();
      await pump(tester, repo);
      await tester.tap(find.text("I don't have it"));
      await tester.pump();
      expect(find.text('Ask the admin'), findsOneWidget);
      await tester.tap(find.text('Ask the admin'));
      await tester.pump();
      await tester.pump();
      expect(find.text('@sajjad'), findsOneWidget);
      expect(find.text('Waiting'), findsOneWidget);
      expect(find.text('Request sent to the admin. Ask the admin for a one-time code.'), findsOneWidget);
      expect(find.text('One-time code from the admin'), findsWidgets);
      expect(find.text('Cancel request'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  test('R-1: login shows "Forgot password?" instead of "Account recovery"', () {
    final src = File('lib/features/authentication/presentation/screens/setup_screen.dart').readAsStringSync();
    expect(src, contains("'Forgot password?'"));
    expect(src, contains('ForgotPasswordScreen222('));
    expect(src, isNot(contains("Text('Account recovery')")));
  });
}
