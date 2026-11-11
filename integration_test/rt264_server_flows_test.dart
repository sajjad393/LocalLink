// Bundle 264: run-time test on GitHub (Android emulator + our Go server).
// One case per job: --dart-define=RT264_CASE=<case> (TODO 264 section F).
// Every step is written as `RT264_STEP PASS|FAIL <name>`; the logs are
// printed at the end (same file as the Send logs button).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:locallink/core/config/app_build.dart';
import 'package:locallink/main.dart' as app;

import 'rt264_helpers.dart';

const String rtCase = String.fromEnvironment('RT264_CASE', defaultValue: 'signup_offline');
// For the 2-phone case: a | b, and b1 (before the reinstall) / b2 (after).
const String rtSide = String.fromEnvironment('RT264_SIDE', defaultValue: 'a');
const String rtPass = 'rt264-pass-Aa1';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('rt264 $rtCase $rtSide', (tester) async {
    final ctl = Ctl264();
    try {
      switch (rtCase) {
        case 'signup_offline':
          await _signupOffline(tester, ctl);
        case 'upload_timer':
          await _uploadTimer(tester, ctl);
        case 'upload_add_open':
        case 'upload_account_open':
        case 'upload_refresh':
          await _uploadNudge(tester, ctl, rtCase.substring('upload_'.length));
        case 'profile_offline':
          await _profileOffline(tester, ctl);
        case 'signed_out':
          await _signedOut(tester, ctl);
        case 'blocked_and_update':
          await _blockedAndUpdate(tester, ctl);
        case 'pairing_needed':
          await _pairingNeeded(tester, ctl);
        case 'key_note':
          await _keyNote(tester, ctl);
        default:
          ctl.step('case', false, 'unknown case $rtCase');
      }
    } catch (e, st) {
      ctl.step('crash', false, '$e ${st.toString().split('\n').take(3).join(' | ')}');
    } finally {
      await ctl.shot('end');
      await dumpLogs(ctl);
      // ignore: avoid_print
      print('RT264_RESULT ${ctl.allPassed ? 'PASS' : 'FAIL'} case=$rtCase side=$rtSide');
    }
    expect(ctl.allPassed, isTrue, reason: ctl.steps.join('\n'));
  }, timeout: const Timeout(Duration(minutes: 40)));
}

Future<void> _openApp(WidgetTester tester) async {
  app.main();
  await idle(tester, const Duration(seconds: 3));
}

/// Welcome -> Create account -> Register -> Your profile -> Chats.
Future<bool> _createAccount(WidgetTester tester, Ctl264 ctl, String user,
    {String step = 'signup'}) async {
  await _openApp(tester);
  await ctl.shot('welcome');
  if (!await tapText(tester, 'Create account', timeout: const Duration(seconds: 40))) {
    ctl.step(step, false, 'no Create account button');
    return false;
  }
  await enterField(tester, 'Username', user);
  await enterField(tester, 'Password', rtPass);
  final reg = find.widgetWithText(FilledButton, 'Register');
  if (reg.evaluate().isEmpty) {
    ctl.step(step, false, 'no Register button');
    return false;
  }
  await tester.tap(reg.first);
  await tester.pump(const Duration(milliseconds: 500));
  await ctl.shot('creating');
  final saved = find.textContaining('Saved on this phone');
  final profile = find.text('Your profile');
  final ok = await waitFor(tester, profile, timeout: const Duration(seconds: 60));
  if (saved.evaluate().isNotEmpty) ctl.step('$step no_saved_dialog', false, 'shown');
  if (!ok) {
    ctl.step(step, false, 'Your profile page did not open in 60 s');
    return false;
  }
  await enterField(tester, 'Display name', 'RT ${user.toUpperCase()}');
  await tapText(tester, 'Save changes');
  final chats = await waitFor(tester, find.text('Chats'), timeout: const Duration(seconds: 30));
  await ctl.shot('chats');
  ctl.step(step, chats, chats ? '' : 'Chats tab not shown');
  return chats;
}

void _checkForbidden(Ctl264 ctl, String where) {
  final shown = shownForbidden();
  ctl.step('no_removed_texts $where', shown.isEmpty, shown.join(', '));
}

// F1
Future<void> _signupOffline(WidgetTester tester, Ctl264 ctl) async {
  await ctl.stop();
  final started = DateTime.now();
  final ok = await _createAccount(tester, ctl, 'rt_a', step: 'F1 signup_offline');
  if (!ok) return;
  final secs = DateTime.now().difference(started).inSeconds;
  ctl.step('F1 chats_within_60s', secs <= 60, 'took ${secs}s');
  _checkForbidden(ctl, 'chats');
  final hidden = await waitLog(tester, 'UI_HIDDEN_263',
      contains: ['card=signup_saved'], timeout: const Duration(seconds: 5));
  // Only logged when the dialog would have shown (server really off).
  ctl.step('F1 log signup_saved', hidden != null, hidden == null ? 'line not seen' : '');
  final search = await waitLog(tester, 'SERVER_SEARCH', timeout: const Duration(seconds: 30));
  ctl.step('F1 log SERVER_SEARCH', search != null);
}

// F2
Future<void> _uploadTimer(WidgetTester tester, Ctl264 ctl) async {
  await _signupOffline(tester, ctl);
  final mark = appLogLines().length;
  await ctl.start();
  final check = await waitLog(tester, 'OFFLINE_ACCOUNT_CHECK',
      contains: ['from=timer'], timeout: const Duration(minutes: 6), after: mark);
  ctl.step('F2 log CHECK from=timer', check != null);
  final done = await waitLog(tester, 'OFFLINE_ACCOUNT_DONE',
      timeout: const Duration(minutes: 6), after: mark);
  ctl.step('F2 log DONE', done != null);
  final users = await ctl.admin('users');
  ctl.step('F2 server has rt_a', users.toString().contains('rt_a'));
  _checkForbidden(ctl, 'chats after upload');
}

// F3
Future<void> _uploadNudge(WidgetTester tester, Ctl264 ctl, String how) async {
  await _signupOffline(tester, ctl);
  final mark = appLogLines().length;
  await ctl.start();
  await idle(tester, const Duration(seconds: 2));
  final from = switch (how) { 'add_open' => 'add_open', 'account_open' => 'account_open', _ => 'refresh' };
  if (how == 'add_open') {
    await tapText(tester, 'People');
    final add = find.byTooltip('Add contact');
    if (await waitFor(tester, add)) await tester.tap(add.first);
    await idle(tester, const Duration(seconds: 2));
    await ctl.shot('add_contact');
    _checkForbidden(ctl, 'add contact');
  } else if (how == 'account_open') {
    await tapText(tester, 'Settings');
    final arrow = find.byKey(const ValueKey('settings_account_arrow'));
    if (await waitFor(tester, arrow)) await tester.tap(arrow.first);
    await idle(tester, const Duration(seconds: 2));
    await ctl.shot('account');
    _checkForbidden(ctl, 'account');
  } else {
    final list = find.byType(Scrollable);
    if (list.evaluate().isNotEmpty) {
      await tester.fling(list.first, const Offset(0, 400), 1200);
    }
    await idle(tester, const Duration(seconds: 2));
  }
  final check = await waitLog(tester, 'OFFLINE_ACCOUNT_CHECK',
      contains: ['from=$from'], timeout: const Duration(seconds: 30), after: mark);
  ctl.step('F3 log CHECK from=$from', check != null);
  final done = await waitLog(tester, 'OFFLINE_ACCOUNT_DONE',
      timeout: const Duration(seconds: 30), after: mark);
  ctl.step('F3 log DONE within 30s', done != null);
}

Future<void> _openOwnProfile(WidgetTester tester) async {
  await tapText(tester, 'Settings');
  final arrow = find.byKey(const ValueKey('settings_account_arrow'));
  // The profile card (name) above the arrow opens the profile.
  final name = find.textContaining('RT ');
  if (await waitFor(tester, name)) {
    await tester.tap(name.first);
  } else if (arrow.evaluate().isNotEmpty) {
    await tester.tap(arrow.first);
  }
  await idle(tester, const Duration(seconds: 2));
}

// F4
Future<void> _profileOffline(WidgetTester tester, Ctl264 ctl) async {
  await ctl.start();
  if (!await _createAccount(tester, ctl, 'rt_a', step: 'F4 signup_online')) return;
  await ctl.stop();
  await idle(tester, const Duration(seconds: 3));
  await _openOwnProfile(tester);
  await ctl.shot('profile');
  final mark = appLogLines().length;
  await enterField(tester, 'Display name', 'RT Offline Name');
  await tapText(tester, 'Save changes');
  final snack = await waitFor(tester, find.text('Profile saved'), timeout: const Duration(seconds: 10));
  ctl.step('F4 snack Profile saved', snack);
  final log = await waitLog(tester, 'PROFILE_SAVED_263',
      contains: ['synced=n'], timeout: const Duration(seconds: 10), after: mark);
  ctl.step('F4 log synced=n', log != null);
  _checkForbidden(ctl, 'profile');
  await ctl.start();
  var seen = false;
  final until = DateTime.now().add(const Duration(minutes: 6));
  while (!seen && DateTime.now().isBefore(until)) {
    await idle(tester, const Duration(seconds: 20));
    final users = await ctl.admin('users', {'q': 'rt_a'});
    seen = users.toString().contains('RT Offline Name');
  }
  ctl.step('F4 server has new name', seen);
}

// F5
Future<void> _signedOut(WidgetTester tester, Ctl264 ctl) async {
  await ctl.start();
  if (!await _createAccount(tester, ctl, 'rt_a', step: 'F5 signup_online')) return;
  await idle(tester, const Duration(seconds: 5));
  final mark = appLogLines().length;
  final res = await ctl.admin('revoke', {'user': 'rt_a'});
  ctl.step('F5 admin revoke', (res['revoked'] ?? 0) is int && (res['revoked'] as int? ?? 0) > 0, '$res');
  final dead = await waitLog(tester, 'SESSION_DEAD_262',
      contains: ['n=3'], timeout: const Duration(minutes: 4), after: mark);
  ctl.step('F5 log SESSION_DEAD_262 n=3', dead != null);
  final card = await waitFor(tester, find.text('Sign in again'), timeout: const Duration(seconds: 30));
  await ctl.shot('signed_out');
  ctl.step('F5 Sign in again shown', card);
  final before = await ctl.admin('count401');
  await idle(tester, const Duration(minutes: 3));
  final after = await ctl.admin('count401');
  final grew = ((after['count'] as int?) ?? 0) - ((before['count'] as int?) ?? 0);
  ctl.step('F5 no 401 for 3 min', grew <= 0, 'new 401 lines=$grew');
}

// F6
Future<void> _blockedAndUpdate(WidgetTester tester, Ctl264 ctl) async {
  await ctl.start();
  if (!await _createAccount(tester, ctl, 'rt_a', step: 'F6 signup_online')) return;
  await idle(tester, const Duration(seconds: 5));
  await ctl.admin('block', {'user': 'rt_a'});
  final blocked = await waitFor(tester, find.textContaining('blocked by admin'),
      timeout: const Duration(minutes: 3));
  await ctl.shot('blocked');
  ctl.step('F6 blocked banner', blocked);
  await ctl.admin('unblock', {'user': 'rt_a'});
  await idle(tester, const Duration(seconds: 10));
  await ctl.admin('version', {'min_build': '${kAppBuild + 1}'});
  final update = await waitFor(tester, find.textContaining('Update needed in'),
      timeout: const Duration(minutes: 5));
  await ctl.shot('update_needed');
  ctl.step('F6 update banner', update);
}

// F7
Future<void> _pairingNeeded(WidgetTester tester, Ctl264 ctl) async {
  await ctl.start(env: 'pairing=1');
  await _openApp(tester);
  if (!await tapText(tester, 'Create account', timeout: const Duration(seconds: 40))) {
    ctl.step('F7 signup', false, 'no Create account button');
    return;
  }
  await enterField(tester, 'Username', 'rt_p');
  await enterField(tester, 'Password', rtPass);
  final reg = find.widgetWithText(FilledButton, 'Register');
  if (reg.evaluate().isNotEmpty) await tester.tap(reg.first);
  final profile = find.text('Your profile');
  if (await waitFor(tester, profile, timeout: const Duration(seconds: 60))) {
    await enterField(tester, 'Display name', 'RT P');
    await tapText(tester, 'Save changes');
  }
  final card = await waitFor(tester, find.text('The server needs a pairing code'),
      timeout: const Duration(minutes: 3));
  await ctl.shot('pairing');
  ctl.step('F7 pairing card', card);
  _checkForbidden(ctl, 'chats with pairing');
}

// F8 (two emulators; may fail without failing the run)
Future<void> _keyNote(WidgetTester tester, Ctl264 ctl) async {
  if (rtSide == 'b2') {
    // B after `pm clear`: sign in again as rt_b (new key).
    await _openApp(tester);
    await tapText(tester, 'Log in', timeout: const Duration(seconds: 40));
    await enterField(tester, 'Username', 'rt_b');
    await enterField(tester, 'Password', rtPass);
    final login = find.widgetWithText(FilledButton, 'Log in');
    if (login.evaluate().isNotEmpty) await tester.tap(login.first);
    final chats = await waitFor(tester, find.text('Chats'), timeout: const Duration(seconds: 90));
    ctl.step('F8 b relogin', chats);
    await idle(tester, const Duration(seconds: 20));
    await ctl.mark('b_relogged');
    await ctl.waitMark('a_checked', seconds: 900);
    return;
  }
  const me = rtSide == 'a' ? 'rt_a' : 'rt_b';
  if (rtSide == 'a') await ctl.start();
  if (rtSide != 'a') await ctl.waitMark('server_up', seconds: 300);
  if (rtSide == 'a') await ctl.mark('server_up');
  if (!await _createAccount(tester, ctl, me, step: 'F8 signup $me')) return;
  if (rtSide == 'a') {
    await ctl.waitMark('b_ready', seconds: 600);
    await tapText(tester, 'People');
    final add = find.byTooltip('Add contact');
    if (await waitFor(tester, add)) await tester.tap(add.first);
    await idle(tester, const Duration(seconds: 2));
    final search = find.byType(TextField);
    if (search.evaluate().isNotEmpty) await tester.enterText(search.first, '@rt_b');
    await idle(tester, const Duration(seconds: 4));
    final addBtn = await tapText(tester, 'Add', timeout: const Duration(seconds: 30));
    if (addBtn) await tapText(tester, 'Add contact', timeout: const Duration(seconds: 5));
    ctl.step('F8 a adds b', addBtn);
    await ctl.mark('a_added');
    await ctl.waitMark('b_accepted', seconds: 600);
    await _sendTo(tester, 'RT B', 'hello from a');
    await ctl.mark('a_sent');
    await ctl.waitMark('b_relogged', seconds: 1200);
    await idle(tester, const Duration(seconds: 30));
    final key = await waitLog(tester, 'KEY_EVENT_263', timeout: const Duration(minutes: 3));
    ctl.step('F8 log KEY_EVENT_263', key != null);
    await _openChat(tester, 'RT B');
    final pill = find.textContaining("security code changed");
    final shown = await waitFor(tester, pill, timeout: const Duration(seconds: 30));
    await ctl.shot('key_pill');
    ctl.step('F8 pill in chat', shown);
    if (shown) {
      await tester.tap(pill.first);
      final page = await waitFor(tester, find.textContaining('Security code'),
          timeout: const Duration(seconds: 10));
      ctl.step('F8 pill opens Security code', page);
    }
    await ctl.mark('a_checked');
  } else {
    await ctl.mark('b_ready');
    await ctl.waitMark('a_added', seconds: 600);
    await tapText(tester, 'People');
    final accepted = await tapText(tester, 'Accept', timeout: const Duration(seconds: 120));
    ctl.step('F8 b accepts', accepted);
    await ctl.mark('b_accepted');
    await ctl.waitMark('a_sent', seconds: 600);
    await _sendTo(tester, 'RT A', 'hello from b');
    await idle(tester, const Duration(seconds: 10));
  }
}

Future<void> _openChat(WidgetTester tester, String name) async {
  await tapText(tester, 'Chats');
  final row = find.textContaining(name);
  if (await waitFor(tester, row, timeout: const Duration(seconds: 60))) {
    await tester.tap(row.first);
    await idle(tester, const Duration(seconds: 2));
  }
}

Future<void> _sendTo(WidgetTester tester, String name, String text) async {
  await tapText(tester, 'People');
  final row = find.textContaining(name);
  if (!await waitFor(tester, row, timeout: const Duration(seconds: 60))) return;
  await tester.tap(row.first);
  await idle(tester, const Duration(seconds: 2));
  await tapText(tester, 'Message', timeout: const Duration(seconds: 5));
  final box = find.widgetWithText(TextField, 'Message');
  if (box.evaluate().isEmpty) return;
  await tester.enterText(box.first, text);
  final send = find.byTooltip('Send message');
  if (send.evaluate().isNotEmpty) await tester.tap(send.first);
  await idle(tester, const Duration(seconds: 3));
}
