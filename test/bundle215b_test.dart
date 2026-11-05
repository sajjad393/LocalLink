import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/features/groups/data/group_change_hub.dart';
import 'package:locallink/features/groups/data/services/group_nearby_service.dart'
    show GroupInviteState;
import 'package:locallink/features/groups/domain/group_repository_contract.dart';
import 'package:locallink/features/groups/presentation/group_people_hub.dart';
import 'package:locallink/features/groups/presentation/screens/group_info_screen.dart';
import 'package:locallink/features/groups/presentation/widgets/group_info_sheets.dart';
import 'package:locallink/features/groups/presentation/widgets/group_nearby_widgets.dart';

/// Bundle 215 (B + C): "Pending" next to a member who has not got the
/// group yet, in Group info; tap → Pending text + Try again.

LocalGroup _g({String origin = 'nearby', int card = 1}) => LocalGroup(
      id: 'g1',
      name: 'Family',
      ownerId: 'me',
      createdAt: '2026-11-03T10:00:00Z',
      createdBy: 'me',
      state: 'active',
      origin: origin,
      cardVersion: card,
    );

GroupMember _m(String id, String name, String role) => GroupMember(
    groupId: 'g1', deviceId: id, role: role, joinedAt: '2026-11-03T10:00:00Z', name: name);

class _Repo implements GroupRepositoryContract {
  _Repo(this.group);
  LocalGroup group;
  final members = [
    _m('me', 'Sajjad', 'owner'),
    _m('d-ali', 'Ali', 'member'),
    _m('d-sum', 'sumaira', 'member'),
  ];
  @override
  Future<List<GroupMember>> listMembers(String groupId) async => members;
  @override
  Future<LocalGroup?> localGroup(String groupId) async => group;
  @override
  Future<LocalGroup?> refreshGroup(String groupId) async => group;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

GroupInviteState _inv(String id, String name, String state, {int at = 0}) =>
    GroupInviteState(memberId: id, name: name, state: state, atMs: at);

Future<void> _frames(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void _unbind() {
  GroupNearbyHub.loadInvites = null;
  GroupNearbyHub.retry = null;
  GroupNearbyHub.inviteCode = null;
  GroupNearbyHub.loadRequests = null;
}

void main() {
  late List<GroupInviteState> invites;
  late List<String> retried;
  final nearBefore = groupMemberNearNow;

  setUp(() {
    GroupPeopleHub.instance = null;
    _unbind();
    invites = [
      _inv('d-ali', 'Ali', 'added'),
      _inv('d-sum', 'sumaira', 'waiting', at: DateTime.now().millisecondsSinceEpoch),
    ];
    retried = [];
    GroupNearbyHub.loadInvites = (gid) async => invites;
    GroupNearbyHub.retry = (gid, id) async => retried.add('$gid:$id');
  });
  tearDown(() {
    _unbind();
    groupMemberNearNow = nearBefore;
  });

  Future<_Repo> open(WidgetTester t, {LocalGroup? group}) async {
    t.view.physicalSize = const Size(800, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final repo = _Repo(group ?? _g());
    await t.pumpWidget(MaterialApp(
        home: GroupInfoScreen(group: repo.group, localDeviceId: 'me', groups: repo)));
    await _frames(t);
    return repo;
  }

  testWidgets('members title + Pending tag + line; others unchanged', (t) async {
    await open(t);
    expect(find.text('3 MEMBERS · 1 PENDING'), findsOneWidget);
    expect(find.byKey(const ValueKey('member_pending_d-sum')), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Gets the group when Nearby or Online'), findsOneWidget);
    expect(find.byKey(const ValueKey('member_pending_d-ali')), findsNothing);
    expect(find.byKey(const ValueKey('member_pending_me')), findsNothing);
    // The tag sits right of her name, on the same line.
    final name = t.getRect(find.text('sumaira'));
    final tag = t.getRect(find.byKey(const ValueKey('member_pending_d-sum')));
    expect(tag.left, greaterThan(name.right));
    expect((tag.center.dy - name.center.dy).abs(), lessThan(4));
  });

  testWidgets('Nearby now → "Nearby now · adding…"', (t) async {
    groupMemberNearNow = (id) => id == 'd-sum';
    await open(t);
    expect(find.text('Nearby now · adding…'), findsOneWidget);
  });

  testWidgets('not reached in 7 days → try again line', (t) async {
    invites = [_inv('d-sum', 'sumaira', 'failed')];
    await open(t);
    expect(find.text('Not reached in 7 days · tap to try again'), findsOneWidget);
    expect(find.text('3 MEMBERS · 1 PENDING'), findsOneWidget);
  });

  testWidgets('she gets the group → tag goes by itself', (t) async {
    await open(t);
    expect(find.text('Pending'), findsOneWidget);
    invites = [_inv('d-ali', 'Ali', 'added'), _inv('d-sum', 'sumaira', 'added')];
    GroupChangeHub.instance.changed('g1');
    await _frames(t);
    expect(find.text('Pending'), findsNothing);
    expect(find.text('3 MEMBERS'), findsOneWidget);
    expect(find.text('Gets the group when Nearby or Online'), findsNothing);
  });

  testWidgets('tap her: Pending text, time, Try again → retry + snackbar', (t) async {
    await open(t);
    await t.tap(find.text('sumaira'));
    await _frames(t);
    expect(find.byKey(const ValueKey('member_sheet_pending')), findsOneWidget);
    expect(
        find.text("sumaira's phone has not got the group yet. It is added by itself "
            'when sumaira is Nearby (Wi-Fi Direct or mesh) or Online.'),
        findsOneWidget);
    expect(find.textContaining('Added by you · today '), findsOneWidget);
    expect(find.byKey(const ValueKey('member_remove')), findsOneWidget); // usual rows stay
    await t.tap(find.byKey(const ValueKey('member_retry')));
    await _frames(t);
    expect(retried, ['g1:d-sum']);
    expect(find.text('Sending the group to sumaira again'), findsOneWidget);
  });

  testWidgets('tap a normal member: no Pending, no Try again', (t) async {
    await open(t);
    await t.tap(find.text('Ali'));
    await _frames(t);
    expect(find.byKey(const ValueKey('group_member_sheet')), findsOneWidget);
    expect(find.byKey(const ValueKey('member_retry')), findsNothing);
    expect(find.byKey(const ValueKey('member_pending_text')), findsNothing);
    expect(find.byKey(const ValueKey('group_member_line')), findsOneWidget);
  });

  testWidgets('server group (no invites) → as today', (t) async {
    await open(t, group: _g(origin: 'server', card: 0));
    expect(find.text('3 MEMBERS'), findsOneWidget);
    expect(find.text('Pending'), findsNothing);
  });

  test('helpers', () {
    expect(groupInvitePending(null), isFalse);
    expect(groupInvitePending(_inv('a', 'A', 'added')), isFalse);
    expect(groupInvitePending(_inv('a', 'A', 'waiting')), isTrue);
    expect(groupInvitePending(_inv('a', 'A', 'failed')), isTrue);
    final now = DateTime(2026, 11, 5, 15);
    expect(groupPendingSince(DateTime(2026, 11, 5, 10, 42).millisecondsSinceEpoch, now: now),
        'Added by you · today 10:42');
    expect(groupPendingSince(DateTime(2026, 11, 3, 9).millisecondsSinceEpoch, now: now),
        'Added by you · 3 Nov');
    expect(groupPendingSince(0), 'Added by you');
  });

  testWidgets('dark theme: Pending readable colours', (t) async {
    await t.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: const Scaffold(body: Center(child: GroupPendingTag()))));
    final text = t.widget<Text>(find.text('Pending'));
    expect(text.style!.color, GroupPendingTag.darkText);
  });
}
