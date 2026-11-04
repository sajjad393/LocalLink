import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/features/groups/domain/group_repository_contract.dart';
import 'package:locallink/features/groups/presentation/group_people_hub.dart';
import 'package:locallink/features/groups/presentation/screens/group_info_screen.dart';
import 'package:locallink/features/groups/data/services/group_nearby_service.dart'
    show GroupJoinRequest;
import 'package:locallink/core/models/group_join_code.dart';
import 'package:locallink/features/groups/presentation/screens/group_qr_screens.dart';
import 'package:locallink/features/groups/presentation/widgets/group_info_sheets.dart';
import 'package:locallink/features/groups/presentation/widgets/group_nearby_widgets.dart';

/// Bundle G4: Join with QR screens (mocks 2 / 33 / 36 / 37 / 38).

LocalGroup _g({
  String owner = 'me',
  String state = 'active',
  String editInfo = 'admins',
  String sendMessages = 'all',
  String addMembers = 'admins',
  String description = 'Lunch plans and office news',
}) =>
    LocalGroup(
      id: 'g1',
      name: 'Office',
      ownerId: owner,
      createdAt: '2026-11-03T10:00:00Z',
      description: description,
      editInfo: editInfo,
      sendMessages: sendMessages,
      addMembers: addMembers,
      createdBy: owner,
      state: state,
    );

GroupMember _m(String id, String name, String role, String joined) =>
    GroupMember(
        groupId: 'g1', deviceId: id, role: role, joinedAt: joined, name: name);

final _owner = _m('me', 'Sajjad', 'owner', '2026-11-03T10:00:00Z');
final _ali = _m('d-ali', 'Ali', 'admin', '2026-11-03T10:00:01Z');
final _sara = _m('d-sara', 'Sara', 'member', '2026-11-03T10:00:02Z');
final _bilal = _m('d-bilal', 'Bilal', 'member', '2026-11-03T10:00:03Z');

class _Repo implements GroupRepositoryContract {
  _Repo(this.group, this.members);
  LocalGroup group;
  List<GroupMember> members;
  final List<String> calls = [];

  @override
  Future<List<GroupMember>> listMembers(String groupId) async => members;
  @override
  Future<LocalGroup?> localGroup(String groupId) async => group;
  @override
  Future<LocalGroup?> refreshGroup(String groupId) async => group;
  @override
  Future<void> removeMember(String groupId, String deviceId) async {
    calls.add('remove:$deviceId');
    members = members.where((m) => m.deviceId != deviceId).toList();
  }

  @override
  Future<void> setAdmin(String groupId, String deviceId,
          {required bool admin}) async =>
      calls.add('admin:$deviceId:$admin');
  @override
  Future<void> leave(String groupId) async {
    calls.add('leave');
    group = group.copyWith(state: 'left');
  }

  @override
  Future<void> deleteLocal(String groupId) async => calls.add('delete');
  @override
  Future<LocalGroup> updateGroup(String groupId,
      {String? name,
      String? description,
      String? editInfo,
      String? sendMessages,
      String? addMembers}) async {
    calls.add('update:${name ?? ''}:${description ?? ''}');
    group = group.copyWith(
        name: name,
        description: description,
        editInfo: editInfo,
        sendMessages: sendMessages,
        addMembers: addMembers);
    return group;
  }

  @override
  Future<void> setPhoto(String groupId, List<int>? jpeg) async {}
  @override
  Future<void> addMember(String groupId, String deviceId) async =>
      calls.add('add:$deviceId');
  @override
  Future<List<LocalGroup>> listGroups() async => [group];
  @override
  Future<List<Device>> availableMemberDevices() async => const [];
  @override
  Future<LocalGroup> createGroup(String name, List<String> memberIds,
          {String description = '',
          String editInfo = 'admins',
          String sendMessages = 'all',
          String addMembers = 'admins',
          List<int>? photoJpeg}) async =>
      group;
}

Future<void> _frames(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(1080, 3000);
  t.view.devicePixelRatio = 2.5;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

String _k(String who) => '$who-key-'.padRight(43, 'x');

GroupJoinCode _code({int until = 1 << 50}) => GroupJoinCode(
      gid: 'g1',
      name: 'Office',
      count: 4,
      issuer: 'me',
      issuerName: 'Sajjad',
      seal: _k('s'),
      sign: _k('g'),
      token: '0123456789abcdef',
      until: until,
      names: const ['Sajjad', 'Ali', 'Sara', 'Bilal'],
    );

GroupJoinRequest _usman() => GroupJoinRequest(
      memberId: 'd-usman',
      name: 'Usman',
      username: 'usman',
      atMs: DateTime(2026, 11, 3, 21, 50).millisecondsSinceEpoch,
      viaNames: const ['Ali'],
    );

void _unbind() {
  GroupNearbyHub.inviteCode = null;
  GroupNearbyHub.approveOf = null;
  GroupNearbyHub.setApprove = null;
  GroupNearbyHub.loadRequests = null;
  GroupNearbyHub.addJoiner = null;
  GroupNearbyHub.ignoreJoiner = null;
  GroupNearbyHub.joinState = null;
  GroupNearbyHub.askToJoin = null;
  GroupNearbyHub.inGroup = null;
}

void main() {
  setUp(() {
    GroupPeopleHub.instance = null;
    _unbind();
  });
  tearDown(_unbind);

  testWidgets('mock 36: Invite with QR - texts, rows, Reset makes a new code',
      (t) async {
    _tall(t);
    final calls = <bool>[];
    GroupNearbyHub.inviteCode = (gid, reset) async {
      calls.add(reset);
      return _code();
    };
    await t.pumpWidget(const MaterialApp(
        home: GroupInviteQrScreen(groupId: 'g1', groupName: 'Office')));
    await _frames(t);
    expect(find.text('Invite with QR'), findsOneWidget);
    expect(find.text('Office'), findsNWidgets(2));
    expect(
        find.textContaining(
            'Anyone who scans this near a member can ask to join. It works without internet.',
            findRichText: true),
        findsOneWidget);
    expect(find.textContaining('Expires in 24 hours.', findRichText: true),
        findsOneWidget);
    expect(find.text('Share code'), findsOneWidget);
    expect(find.text('Send the picture to a friend'), findsOneWidget);
    expect(find.text('Reset code'), findsOneWidget);
    expect(find.text('The old code stops working'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    final box = t.getSize(find.byKey(const ValueKey('group_qr_box')));
    expect(box, const Size(210, 210));
    await t.tap(find.text('Reset code'));
    await _frames(t);
    expect(calls, [false, true]);
  });

  testWidgets('mock 38: scanner phone - Ask to join, then Requested ✓',
      (t) async {
    _tall(t);
    final asked = <String>[];
    var state = 'none';
    GroupNearbyHub.joinState = (gid) async => state;
    GroupNearbyHub.inGroup = (gid) async => false;
    GroupNearbyHub.askToJoin = (code) async {
      asked.add(code.gid);
      state = 'asked';
    };
    await t.pumpWidget(MaterialApp(home: JoinGroupScreen(code: _code())));
    await _frames(t);
    expect(find.text('Join group'), findsOneWidget);
    expect(find.text('Office'), findsOneWidget);
    expect(find.text("Group · 4 members · from Sajjad's code"), findsOneWidget);
    await t.tap(find.text('Ask to join'));
    await _frames(t);
    expect(asked, ['g1']);
    expect(find.text('Requested ✓'), findsOneWidget);
    expect(
        find.text('An admin must add you. This stays for 24 hours. '
            'You get "Sajjad added you" when it is done.'),
        findsOneWidget);
  });

  testWidgets('from the camera: asks at once', (t) async {
    _tall(t);
    final asked = <String>[];
    var state = 'none';
    GroupNearbyHub.joinState = (gid) async => state;
    GroupNearbyHub.inGroup = (gid) async => false;
    GroupNearbyHub.askToJoin = (code) async {
      asked.add(code.gid);
      state = 'asked';
    };
    await t.pumpWidget(
        MaterialApp(home: JoinGroupScreen(code: _code(), autoAsk: true)));
    await _frames(t);
    expect(asked, ['g1']);
    expect(find.text('Requested ✓'), findsOneWidget);
    expect(find.text('Ask to join'), findsNothing);
  });

  testWidgets('expired code text', (t) async {
    _tall(t);
    await t
        .pumpWidget(MaterialApp(home: JoinGroupScreen(code: _code(until: 1))));
    await _frames(t);
    expect(find.text('This group code has expired. Ask for a new one.'),
        findsOneWidget);
    expect(find.text('Ask to join'), findsNothing);
  });

  testWidgets('mock 37: request sheet - who, line, hint, Add / Ignore',
      (t) async {
    bool? result;
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async =>
                result = await showJoinRequestSheet(context, _usman()),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await _frames(t);
    expect(find.text('Usman'), findsOneWidget);
    expect(find.text('@usman · scanned the QR · 9:50 PM'), findsOneWidget);
    expect(
        find.text('Usman is not in your friends. Ali (member) is his friend.'),
        findsOneWidget);
    expect(find.text('Add to group'), findsOneWidget);
    expect(find.text('Ignore'), findsOneWidget);
    await t.tap(find.text('Add to group'));
    await _frames(t);
    expect(result, isTrue);
  });

  test('request hint variants', () {
    expect(
        joinRequestHint(const GroupJoinRequest(
            memberId: 'x', name: 'Usman', username: '', atMs: 0)),
        'Usman is not in your friends.');
    expect(
        joinRequestHint(const GroupJoinRequest(
            memberId: 'x', name: 'Usman', username: '', atMs: 0, friend: true)),
        'Usman is in your friends.');
  });

  testWidgets('mock 33: Approve new members switch (Nearby groups)', (t) async {
    _tall(t);
    final saved = <bool>[];
    await t.pumpWidget(MaterialApp(
      home: GroupSettingsScreen(
        groupName: 'Office',
        editInfo: 'admins',
        sendMessages: 'all',
        addMembers: 'admins',
        onChange: (f, v) async {},
        approve: false,
        onApprove: (on) async => saved.add(on),
      ),
    ));
    await _frames(t);
    expect(find.text('Approve new members'), findsOneWidget);
    expect(find.text('Admins approve people who join by QR'), findsOneWidget);
    // below the choices, above the grey line
    final row = t.getTopLeft(find.text('Approve new members')).dy;
    expect(row,
        greaterThan(t.getTopLeft(find.text('Includes the group QR code')).dy));
    expect(
        row,
        lessThan(t
            .getTopLeft(find.text('Only admins can see and change these.'))
            .dy));
    await t.tap(find.byKey(const ValueKey('set_approve_switch')));
    await _frames(t);
    expect(saved, [true]);
  });

  testWidgets('mock 28 / 37: Invite with QR row + orange request card',
      (t) async {
    _tall(t);
    final repo = _Repo(_g().copyWith(origin: 'nearby', cardVersion: 1),
        [_owner, _ali, _sara, _bilal]);
    final added = <String>[];
    var reqs = [_usman()];
    GroupNearbyHub.inviteCode = (gid, reset) async => _code();
    GroupNearbyHub.loadRequests = (gid) async => reqs;
    GroupNearbyHub.addJoiner = (gid, id) async {
      added.add(id);
      reqs = [];
    };
    await t.pumpWidget(MaterialApp(
        home: GroupInfoScreen(
            group: repo.group, localDeviceId: 'me', groups: repo)));
    await _frames(t);
    expect(find.text('Invite with QR'), findsOneWidget);
    expect(find.text('Friends of friends scan to join'), findsOneWidget);
    expect(find.text('1 request to join'), findsOneWidget);
    expect(find.text('Usman scanned the group QR'), findsOneWidget);
    // card sits above the members label
    expect(t.getTopLeft(find.text('1 request to join')).dy,
        lessThan(t.getTopLeft(find.text('4 MEMBERS')).dy));
    await t.tap(find.text('1 request to join'));
    await _frames(t);
    await t.tap(find.text('Add to group'));
    await _frames(t);
    expect(added, ['d-usman']);
    expect(find.text('1 request to join'), findsNothing);
  });

  testWidgets('server-only group: no QR row, no card', (t) async {
    _tall(t);
    final repo = _Repo(_g(), [_owner, _ali]);
    GroupNearbyHub.inviteCode = (gid, reset) async => _code();
    GroupNearbyHub.loadRequests = (gid) async => [_usman()];
    await t.pumpWidget(MaterialApp(
        home: GroupInfoScreen(
            group: repo.group, localDeviceId: 'me', groups: repo)));
    await _frames(t);
    expect(find.text('Invite with QR'), findsNothing);
    expect(find.text('1 request to join'), findsNothing);
  });
}
