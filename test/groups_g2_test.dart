import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/core/models/group_event.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/features/groups/domain/group_repository_contract.dart';
import 'package:locallink/features/groups/presentation/group_people_hub.dart';
import 'package:locallink/features/groups/presentation/screens/group_info_screen.dart';
import 'package:locallink/features/groups/presentation/screens/new_group_screen.dart';
import 'package:locallink/features/groups/presentation/widgets/group_sheets.dart';

/// Bundle G2: admins / Group info / exit (mock 4, 25-33, 35).

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

Widget _info(_Repo repo, {String self = 'me'}) => MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                final r = await Navigator.push<String>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GroupInfoScreen(
                        group: repo.group, localDeviceId: self, groups: repo),
                  ),
                );
                popped = r;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

String? popped;

Future<void> _open(WidgetTester t, _Repo repo, {String self = 'me'}) async {
  popped = null;
  await t.pumpWidget(_info(repo, self: self));
  await t.tap(find.text('open'));
  await _frames(t);
}

void main() {
  setUp(() => GroupPeopleHub.instance = null);

  group('GroupEvent lines', () {
    test('create by me = two lines (mock 6)', () {
      final e = GroupEvent.parse(
          'llev:v1:{"k":"create","by":"me","t":["a","s"],"n":"Office","nm":{"a":"Ali","s":"Sara"}}')!;
      expect(e.lines('me'),
          ['You created group "Office"', 'You added Ali and Sara']);
    });
    test('added me / removed me / owner hand-over / settings', () {
      final add = GroupEvent.parse(
          'llev:v1:{"k":"add","by":"a","t":["me"],"nm":{"a":"Ali"}}')!;
      expect(add.preview('me'), 'Ali added you');
      expect(add.addsMe('me'), isTrue);
      expect(add.countsAsUnread('me'), isTrue);
      final rm = GroupEvent.parse(
          'llev:v1:{"k":"remove","by":"s","t":["me"],"nm":{"s":"Sajjad"}}')!;
      expect(rm.removesMe('me'), isTrue);
      expect(rm.preview('me'), 'Sajjad removed you');
      final leave = GroupEvent.parse(
          'llev:v1:{"k":"leave","by":"s","o":"a","nm":{"s":"Sajjad","a":"Ali"}}')!;
      expect(leave.lines('me'), ['Sajjad left', 'Ali is now the group owner']);
      final set = GroupEvent.parse(
          'llev:v1:{"k":"set","by":"a","f":"send_messages","v":"admins","nm":{"a":"Ali"}}')!;
      expect(set.preview('me'),
          'Ali changed this group so only admins can send messages');
      expect(GroupEvent.parse('hello'), isNull);
    });
  });

  group('GroupRules', () {
    test('owner, admin and member rights', () {
      final members = [_owner, _ali, _sara];
      final owner = GroupRules(_g(), members, 'me');
      expect(owner.isOwner, isTrue);
      expect(owner.canRemove(_ali), isTrue);
      expect(owner.canDismissAdmin(_ali), isTrue);
      expect(owner.nextOwner?.deviceId, 'd-ali');
      final admin = GroupRules(_g(), members, 'd-ali');
      expect(admin.canRemove(_sara), isTrue);
      expect(admin.canRemove(_owner), isFalse);
      expect(admin.canDismissAdmin(_ali), isFalse);
      final member = GroupRules(_g(sendMessages: 'admins'), members, 'd-sara');
      expect(member.canSend, isFalse);
      expect(member.canAdd, isFalse);
      expect(member.canEdit, isFalse);
      expect(member.canRemove(_ali), isFalse);
      final left = GroupRules(_g(state: 'left'), members, 'me');
      expect(left.canSend, isFalse);
      expect(left.canEdit, isFalse);
    });
    test('next owner = oldest member when there is no admin', () {
      final r = GroupRules(_g(), [_owner, _bilal, _sara], 'me');
      expect(r.nextOwner?.deviceId, 'd-sara');
    });
  });

  group('mock 27 / 28: Group info', () {
    testWidgets('owner view: header, actions, members with labels, Exit',
        (t) async {
      _tall(t);
      await _open(t, _Repo(_g(), [_owner, _ali, _sara]));
      expect(find.text('Office'), findsOneWidget);
      expect(find.text('Group · 3 members'), findsOneWidget);
      expect(find.byKey(const ValueKey('info_name_edit')), findsOneWidget);
      expect(find.byKey(const ValueKey('info_add')), findsOneWidget);
      expect(find.byKey(const ValueKey('info_search')), findsOneWidget);
      expect(find.byKey(const ValueKey('info_mute')), findsOneWidget);
      expect(find.text('Lunch plans and office news'), findsOneWidget);
      expect(find.text('Created by You · 3 Nov 2026'), findsOneWidget);
      expect(find.text('Mute notifications'), findsOneWidget);
      expect(find.text('Only admins add people'), findsOneWidget);
      expect(find.text('3 MEMBERS'), findsOneWidget);
      expect(find.text('Add members'), findsOneWidget);
      expect(find.text('Owner'), findsOneWidget);
      expect(find.text('Admin'), findsOneWidget);
      expect(find.text('You'), findsOneWidget);
      expect(find.text('Exit group'), findsOneWidget);
      expect(find.text('Your old messages stay on this phone'), findsOneWidget);
      // Not in G2 (agreed): media strip. QR invite (G4) = Nearby groups only.
      expect(find.textContaining('MEDIA'), findsNothing);
      expect(find.text('Invite with QR'), findsNothing);
    });

    testWidgets('mock 29 + 30: tap a member, remove asks first', (t) async {
      _tall(t);
      final repo = _Repo(_g(), [_owner, _ali, _sara]);
      await _open(t, repo);
      await t.tap(find.byKey(const ValueKey('member_d-sara')));
      await _frames(t);
      // Not a friend (no hub) -> 29b look.
      expect(find.text('Not your friend · in this group'), findsOneWidget);
      expect(find.text('Make group admin'), findsOneWidget);
      expect(find.text('Remove from group'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('member_remove')));
      await _frames(t);
      expect(find.text('Remove Sara from "Office"?'), findsOneWidget);
      expect(
          find.text(
              'Sara will see "Sajjad removed you". They keep the old messages but get no new ones.'),
          findsOneWidget);
      await t.tap(find.byKey(const ValueKey('remove_member_confirm')));
      await _frames(t);
      expect(repo.calls, ['remove:d-sara']);
      expect(find.text('Group · 2 members'), findsOneWidget);
    });

    testWidgets('make admin from the member sheet', (t) async {
      _tall(t);
      final repo = _Repo(_g(), [_owner, _ali, _sara]);
      await _open(t, repo);
      await t.tap(find.byKey(const ValueKey('member_d-sara')));
      await _frames(t);
      await t.tap(find.byKey(const ValueKey('member_make_admin')));
      await _frames(t);
      expect(repo.calls, ['admin:d-sara:true']);
    });

    testWidgets('mock 31: owner exit names the new owner', (t) async {
      _tall(t);
      final repo = _Repo(_g(), [_owner, _ali, _sara]);
      await _open(t, repo);
      await t.tap(find.byKey(const ValueKey('info_exit')));
      await _frames(t);
      expect(find.text('Exit "Office"?'), findsOneWidget);
      expect(find.text('Members see "Sajjad left".'), findsOneWidget);
      expect(find.textContaining('(admin) becomes the new owner.'),
          findsOneWidget);
      await t.tap(find.byKey(const ValueKey('exit_group_confirm')));
      await _frames(t);
      expect(repo.calls, ['leave']);
      // Read only now: Delete group instead of Exit.
      expect(find.byKey(const ValueKey('info_delete')), findsOneWidget);
      expect(find.byKey(const ValueKey('info_exit')), findsNothing);
      expect(find.byKey(const ValueKey('info_add')), findsNothing);
    });

    testWidgets('member view: no settings, no add, no admin tools',
        (t) async {
      _tall(t);
      await _open(t, _Repo(_g(owner: 'd-ali'), [
        _m('d-ali', 'Ali', 'owner', '1'),
        _m('me', 'Sajjad', 'member', '2'),
        _sara,
      ]));
      expect(find.byKey(const ValueKey('info_settings')), findsNothing);
      expect(find.byKey(const ValueKey('info_add')), findsNothing);
      expect(find.byKey(const ValueKey('info_add_members')), findsNothing);
      expect(find.byKey(const ValueKey('info_name_edit')), findsNothing);
      await t.tap(find.byKey(const ValueKey('member_d-sara')));
      await _frames(t);
      expect(find.text('Make group admin'), findsNothing);
      expect(find.text('Remove from group'), findsNothing);
    });

    testWidgets('removed: Delete group asks first, then pops "deleted"',
        (t) async {
      _tall(t);
      final repo = _Repo(_g(state: 'removed'), [_owner, _ali]);
      await _open(t, repo);
      await t.tap(find.byKey(const ValueKey('info_delete')));
      await _frames(t);
      expect(find.text('Delete "Office"?'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('delete_group_confirm')));
      await _frames(t);
      expect(repo.calls, ['delete']);
      expect(popped, 'deleted');
    });

    testWidgets('mock 32: Edit group saves name + description', (t) async {
      _tall(t);
      final repo = _Repo(_g(), [_owner, _ali]);
      await _open(t, repo);
      await t.tap(find.byKey(const ValueKey('info_name')));
      await _frames(t);
      expect(find.text('Edit group'), findsOneWidget);
      expect(find.text('6/80'), findsOneWidget);
      await t.enterText(find.byKey(const ValueKey('edit_group_name')), 'Team');
      await t.pump();
      await t.tap(find.byKey(const ValueKey('edit_group_save')));
      await _frames(t);
      expect(repo.calls, ['update:Team:']);
      expect(find.text('Team'), findsOneWidget);
    });

    testWidgets('Search pops "search"', (t) async {
      _tall(t);
      await _open(t, _Repo(_g(), [_owner]));
      await t.tap(find.byKey(const ValueKey('info_search')));
      await _frames(t);
      expect(popped, 'search');
    });
  });

  group('mock 33: Group settings', () {
    testWidgets('a tap saves one choice; a refusal puts it back', (t) async {
      final changes = <String>[];
      var fail = false;
      await t.pumpWidget(MaterialApp(
        home: GroupSettingsScreen(
          groupName: 'Office',
          editInfo: 'admins',
          sendMessages: 'all',
          addMembers: 'admins',
          onChange: (f, v) async {
            if (fail) {
              throw GroupActionException('GROUP_ADMINS_ONLY', 'x', 403);
            }
            changes.add('$f=$v');
          },
        ),
      ));
      await _frames(t);
      expect(find.text('ADMINS DECIDE'), findsOneWidget);
      expect(find.text('Only admins can see and change these.'), findsOneWidget);
      expect(find.text('Approve new members'), findsNothing); // G4: Nearby only
      await t.tap(find.byKey(const ValueKey('set_send_messages_admins')));
      await _frames(t);
      expect(changes, ['send_messages=admins']);
      fail = true;
      await t.tap(find.byKey(const ValueKey('set_add_members_all')));
      await _frames(t);
      expect(changes, ['send_messages=admins']);
      expect(find.text('Only admins can do this.'), findsOneWidget);
    });
  });

  group('mock 4: name, photo, description, settings', () {
    testWidgets('Create passes description + settings', (t) async {
      _tall(t);
      GroupCreateOptions? got;
      await t.pumpWidget(MaterialApp(
        home: NewGroupNameScreen(
          people: const [GroupFriend(deviceId: 'd-ali', name: 'Ali')],
          onCreate: (name, people, options) async {
            got = options;
            return GroupCreateResult(_g());
          },
        ),
      ));
      await _frames(t);
      expect(find.text('Name and photo'), findsOneWidget);
      expect(find.text('Add group photo (optional)'), findsOneWidget);
      expect(find.text('Description (optional)'), findsOneWidget);
      expect(find.text('SETTINGS'), findsOneWidget);
      expect(find.text('Only admins add people · Everyone can send'),
          findsOneWidget);
      await t.tap(find.byKey(const ValueKey('new_group_settings')));
      await _frames(t);
      await t.tap(find.byKey(const ValueKey('set_send_messages_admins')));
      await _frames(t);
      await t.pageBack();
      await _frames(t);
      expect(find.text('Only admins add people · Only admins send'),
          findsOneWidget);
      await t.enterText(find.byKey(const ValueKey('new_group_name')), 'Office');
      await t.enterText(
          find.byKey(const ValueKey('new_group_description')), 'Lunch');
      await t.pump();
      await t.tap(find.byKey(const ValueKey('new_group_create')));
      await _frames(t);
      expect(got?.description, 'Lunch');
      expect(got?.sendMessages, 'admins');
      expect(got?.addMembers, 'admins');
      expect(got?.photoJpeg, isNull);
    });
  });

  group('mock 35: Add members', () {
    testWidgets('members already in are dim; picked come back', (t) async {
      _tall(t);
      List<GroupFriend>? result;
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await Navigator.push<List<GroupFriend>>(
                context,
                MaterialPageRoute(
                  builder: (_) => GroupAddMembersScreen(
                    groupName: 'Office',
                    memberIds: const {'me', 'd-ali'},
                    loadFriends: () async => const [
                      GroupFriend(deviceId: 'd-ali', name: 'Ali'),
                      GroupFriend(deviceId: 'd-hina', name: 'Hina'),
                    ],
                  ),
                ),
              );
            },
            child: const Text('go'),
          ),
        ),
      ));
      await t.tap(find.text('go'));
      await _frames(t);
      expect(find.text('Office · 1 of 32'), findsOneWidget);
      expect(find.text('Already in the group'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('add_pick_d-ali')));
      await t.tap(find.byKey(const ValueKey('add_pick_d-hina')));
      await t.pump();
      expect(find.text('Office · 2 of 32'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('add_members_done')));
      await _frames(t);
      expect(result?.map((f) => f.deviceId), ['d-hina']);
    });
  });

  group('mock 11 (G2): hold a group row', () {
    testWidgets('left / removed group offers Delete group', (t) async {
      GroupRowChoice? got;
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              got = await showGroupRowSheet(context,
                  name: 'Office', memberCount: 3, muted: false, active: false);
            },
            child: const Text('go'),
          ),
        ),
      ));
      await t.tap(find.text('go'));
      await _frames(t);
      expect(find.text('Exit group'), findsNothing);
      await t.tap(find.text('Delete group'));
      await _frames(t);
      expect(got, GroupRowChoice.delete);
    });
  });
}
