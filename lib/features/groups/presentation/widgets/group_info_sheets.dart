import 'package:flutter/material.dart';
import 'package:locallink/core/widgets/admin_crown.dart';
import 'package:image_picker/image_picker.dart';

import 'package:locallink/core/models/group.dart';
import 'package:locallink/core/presence/presence_hub.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/core/widgets/account_avatar.dart';
import 'package:locallink/features/groups/data/services/group_nearby_service.dart'
    show GroupInviteState, GroupJoinRequest;
import 'package:locallink/features/groups/presentation/widgets/group_nearby_widgets.dart'
    show GroupPendingTag;
import 'package:locallink/features/groups/presentation/widgets/group_sheets.dart';

/// Bundle G2: the Group info bottom sheets of the approved mock (G0).
///
/// * [showGroupPhotoSheet]   mock 5   - Camera / Gallery / Remove photo.
/// * [showGroupMemberSheet]  mock 29 / 29b - tap a member.
/// * [showRemoveMemberSheet] mock 30  - asks first.
/// * [showExitGroupSheet]    mock 31  - asks first, owner hand-over.
/// * [showDeleteGroupSheet]  after exit / removal.
/// * [showEditGroupSheet]    mock 32  - name + description.

/// Server limit for a group photo.
const int kGroupPhotoMaxBytes = 256 * 1024;

Widget _title(BuildContext context, String text) => Padding(
      padding: const EdgeInsets.fromLTRB(2, 2, 2, 10),
      child: Text(text,
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontSize: 18, fontWeight: FontWeight.w700, height: 1.3)),
    );

Widget _hint(BuildContext context, String text) => Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 4),
      child: Text(text,
          style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: Theme.of(context).colorScheme.onSurfaceVariant)),
    );

enum _Big { red, blue, ghost }

Widget _big(BuildContext context, _Big kind, String label, VoidCallback onTap,
    {Key? key}) {
  final colors = Theme.of(context).colorScheme;
  const shape = StadiumBorder();
  const size = Size.fromHeight(48);
  const text =
      TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, letterSpacing: 0);
  final Widget button = switch (kind) {
    _Big.red => FilledButton(
        key: key,
        onPressed: onTap,
        style: FilledButton.styleFrom(
            backgroundColor: colors.error,
            foregroundColor: colors.onError,
            minimumSize: size,
            shape: shape,
            textStyle: text),
        child: Text(label),
      ),
    _Big.blue => FilledButton(
        key: key,
        onPressed: onTap,
        style: FilledButton.styleFrom(
            minimumSize: size, shape: shape, textStyle: text),
        child: Text(label),
      ),
    _Big.ghost => TextButton(
        key: key,
        onPressed: onTap,
        style:
            TextButton.styleFrom(minimumSize: size, shape: shape, textStyle: text),
        child: Text(label),
      ),
  };
  return Padding(padding: const EdgeInsets.only(top: 10), child: button);
}

Future<T?> _sheet<T>(BuildContext context, Key key, List<Widget> Function(BuildContext) children) {
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
      child: SingleChildScrollView(
        key: key,
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children(sheetContext),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------- mock 5

/// What the photo sheet gave: new JPEG bytes, or "remove".
class GroupPhotoPick {
  const GroupPhotoPick.photo(List<int> this.bytes) : remove = false;
  const GroupPhotoPick.remove()
      : bytes = null,
        remove = true;
  final List<int>? bytes;
  final bool remove;
}

enum _PhotoChoice { camera, gallery, remove }

/// Mock 5: "Group photo" - Camera / Gallery / Remove photo / Cancel.
/// The picture is made small (512 px, JPEG) so it fits the 256 KB limit.
Future<GroupPhotoPick?> showGroupPhotoSheet(BuildContext context,
    {required bool hasPhoto, ImagePicker? picker}) async {
  final choice = await _sheet<_PhotoChoice>(
    context,
    const ValueKey('group_photo_sheet'),
    (c) => [
      _title(c, 'Group photo'),
      GroupSheetAction(
        key: const ValueKey('group_photo_camera'),
        icon: Icons.photo_camera_outlined,
        title: 'Camera',
        onTap: () => Navigator.pop(c, _PhotoChoice.camera),
      ),
      GroupSheetAction(
        key: const ValueKey('group_photo_gallery'),
        icon: Icons.photo_library_outlined,
        title: 'Gallery',
        onTap: () => Navigator.pop(c, _PhotoChoice.gallery),
      ),
      if (hasPhoto)
        GroupSheetAction(
          key: const ValueKey('group_photo_remove'),
          icon: Icons.delete_outline_rounded,
          title: 'Remove photo',
          red: true,
          onTap: () => Navigator.pop(c, _PhotoChoice.remove),
        ),
      _big(c, _Big.ghost, 'Cancel', () => Navigator.pop(c),
          key: const ValueKey('group_photo_cancel')),
    ],
  );
  if (choice == null) return null;
  if (choice == _PhotoChoice.remove) return const GroupPhotoPick.remove();
  try {
    final file = await (picker ?? ImagePicker()).pickImage(
      source: choice == _PhotoChoice.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 78,
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    if (bytes.length > kGroupPhotoMaxBytes) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('This photo is too big. Try another one.')));
      }
      return null;
    }
    return GroupPhotoPick.photo(bytes);
  } catch (error) {
    AppLogger.warning('GROUP_PHOTO_PICK_FAILED', detail: '$error');
    return null;
  }
}

// ------------------------------------------------------------ mock 29/29b

enum GroupMemberChoice { message, profile, addFriend, makeAdmin, dismissAdmin, remove, retry }

/// Bundle 215 (C2): "Added by you · today 10:42" / "· 3 Nov".
String groupPendingSince(int atMs, {DateTime? now}) {
  if (atMs <= 0) return 'Added by you';
  final t = DateTime.fromMillisecondsSinceEpoch(atMs);
  final n = now ?? DateTime.now();
  final hh = t.hour.toString().padLeft(2, '0');
  final mm = t.minute.toString().padLeft(2, '0');
  if (t.year == n.year && t.month == n.month && t.day == n.day) {
    return 'Added by you · today $hh:$mm';
  }
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return 'Added by you · ${t.day} ${months[t.month - 1]}';
}

/// Mock 29 (friend) / 29b (not a friend): tap a member in Group info.
Future<GroupMemberChoice?> showGroupMemberSheet(
  BuildContext context, {
  required GroupMember member,
  required bool friend,
  required bool canMessage,
  required bool canAddFriend,
  required bool canMakeAdmin,
  required bool canDismissAdmin,
  required bool canRemove,
  String username = '',
  GroupInviteState? pending,
  bool canRetry = false,
}) {
  final name = member.name.trim().isEmpty ? 'Group member' : member.name.trim();
  final status = PresenceHub.instance.statusOf(member.deviceId).label;
  final wait = pending != null && pending.state != 'added' ? pending : null;
  final line = friend
      ? (username.isEmpty ? status : '@$username · $status')
      : 'Not your friend · in this group';
  return _sheet<GroupMemberChoice>(
    context,
    const ValueKey('group_member_sheet'),
    (c) {
      final colors = Theme.of(c).colorScheme;
      return [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
          child: Row(
            children: [
              AccountAvatar(name: name, radius: 23, peerId: member.deviceId),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15.5, fontWeight: FontWeight.w700)),
                    if (wait != null)
                      const Padding(
                        padding: EdgeInsets.only(top: 3),
                        child: GroupPendingTag(key: ValueKey('member_sheet_pending')),
                      )
                    else
                    Text(line,
                        key: const ValueKey('group_member_line'),
                        style: TextStyle(
                            fontSize: 13, color: colors.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Bundle 215 (C2/C3, mock 215 page 4): why pending + Try again.
        if (wait != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 2, 2, 4),
            child: Text(
                wait.state == 'failed'
                    ? "Not reached in 7 days. Tap Try again to send the group to $name again."
                    : "$name's phone has not got the group yet. It is added by itself when $name is Nearby (Wi-Fi Direct or mesh) or Online.",
                key: const ValueKey('member_pending_text'),
                style: TextStyle(fontSize: 13.5, color: colors.onSurface, height: 1.35)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
            child: Text(groupPendingSince(wait.atMs),
                key: const ValueKey('member_pending_since'),
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
          ),
          if (canRetry)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _big(c, _Big.blue, 'Try again',
                  () => Navigator.pop(c, GroupMemberChoice.retry),
                  key: const ValueKey('member_retry')),
            ),
        ],
        if (friend && canMessage)
          GroupSheetAction(
            key: const ValueKey('member_message'),
            icon: Icons.chat_bubble_outline_rounded,
            title: 'Message $name',
            onTap: () => Navigator.pop(c, GroupMemberChoice.message),
          ),
        if (friend)
          GroupSheetAction(
            key: const ValueKey('member_profile'),
            icon: Icons.person_outline_rounded,
            title: 'View profile',
            onTap: () => Navigator.pop(c, GroupMemberChoice.profile),
          ),
        if (!friend && canAddFriend)
          GroupSheetAction(
            key: const ValueKey('member_add_friend'),
            icon: Icons.person_add_alt_outlined,
            title: 'Add friend',
            subtitle: 'Sends a friend request',
            onTap: () => Navigator.pop(c, GroupMemberChoice.addFriend),
          ),
        if (canMakeAdmin)
          GroupSheetAction(
            key: const ValueKey('member_make_admin'),
            icon: Icons.star_border_rounded,
            title: 'Make group admin',
            onTap: () => Navigator.pop(c, GroupMemberChoice.makeAdmin),
          ),
        if (canDismissAdmin)
          GroupSheetAction(
            key: const ValueKey('member_dismiss_admin'),
            icon: Icons.star_outline_rounded,
            title: 'Dismiss as admin',
            onTap: () => Navigator.pop(c, GroupMemberChoice.dismissAdmin),
          ),
        if (canRemove)
          GroupSheetAction(
            key: const ValueKey('member_remove'),
            icon: Icons.person_remove_outlined,
            title: 'Remove from group',
            red: true,
            onTap: () => Navigator.pop(c, GroupMemberChoice.remove),
          ),
        if (!friend)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _hint(c,
                'No "Message" here: you can only chat 1:1 with friends. In the group you can still talk.'),
          ),
        _big(c, _Big.ghost, 'Close', () => Navigator.pop(c),
            key: const ValueKey('member_close')),
      ];
    },
  );
}

/// "View profile": photo, name, @username and status.
Future<void> showGroupMemberProfile(BuildContext context,
    {required GroupMember member, String username = ''}) {
  final name = member.name.trim().isEmpty ? 'Group member' : member.name.trim();
  return _sheet<void>(
    context,
    const ValueKey('member_profile_sheet'),
    (c) {
      final colors = Theme.of(c).colorScheme;
      return [
        Center(child: AccountAvatar(name: name, radius: 44, peerId: member.deviceId)),
        const SizedBox(height: 12),
        Text(name,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        if (username.isNotEmpty)
          Text('@$username',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: colors.onSurfaceVariant)),
        AdminRoleLine(id: member.deviceId), // Bundle 214 (D7)
        const SizedBox(height: 4),
        Text(PresenceHub.instance.statusOf(member.deviceId).label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant)),
        _big(c, _Big.ghost, 'Close', () => Navigator.pop(c)),
      ];
    },
  );
}

// ---------------------------------------------------------------- mock 30

Future<bool> showRemoveMemberSheet(BuildContext context,
    {required String name, required String groupName, required String me}) async {
  final ok = await _sheet<bool>(
    context,
    const ValueKey('remove_member_sheet'),
    (c) => [
      _title(c, 'Remove $name from "$groupName"?'),
      _hint(c,
          '$name will see "$me removed you". They keep the old messages but get no new ones.'),
      _big(c, _Big.red, 'Remove', () => Navigator.pop(c, true),
          key: const ValueKey('remove_member_confirm')),
      _big(c, _Big.ghost, 'Cancel', () => Navigator.pop(c, false)),
    ],
  );
  return ok == true;
}

// ---------------------------------------------------------------- mock 31

Widget _points(BuildContext context, List<InlineSpan> points) {
  final colors = Theme.of(context).colorScheme;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final p in points)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(top: 7, right: 10),
                decoration:
                    BoxDecoration(color: colors.outline, shape: BoxShape.circle),
              ),
              Expanded(
                child: Text.rich(p,
                    style: TextStyle(
                        fontSize: 14, height: 1.35, color: colors.onSurface)),
              ),
            ],
          ),
        ),
    ],
  );
}

/// Mock 31: Exit "Office"? [nextOwner] = the new owner when I am the owner.
Future<bool> showExitGroupSheet(BuildContext context,
    {required String groupName,
    required String me,
    bool owner = false,
    String nextOwner = '',
    bool nextIsAdmin = false}) async {
  final ok = await _sheet<bool>(
    context,
    const ValueKey('exit_group_sheet'),
    (c) => [
      _title(c, 'Exit "$groupName"?'),
      _points(c, [
        TextSpan(text: 'Members see "$me left".'),
        const TextSpan(
            text:
                'Old messages stay on your phone (read only). You can delete the group later.'),
        if (owner && nextOwner.isNotEmpty)
          TextSpan(children: [
            const TextSpan(text: 'You are the owner: '),
            TextSpan(
                text: nextOwner,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(
                text: nextIsAdmin
                    ? ' (admin) becomes the new owner.'
                    : ' becomes the new owner.'),
          ]),
      ]),
      _big(c, _Big.red, 'Exit group', () => Navigator.pop(c, true),
          key: const ValueKey('exit_group_confirm')),
      _big(c, _Big.ghost, 'Cancel', () => Navigator.pop(c, false)),
    ],
  );
  return ok == true;
}

/// "Delete group" (after exit / removal): asks first.
Future<bool> showDeleteGroupSheet(BuildContext context,
    {required String groupName}) async {
  final ok = await _sheet<bool>(
    context,
    const ValueKey('delete_group_sheet'),
    (c) => [
      _title(c, 'Delete "$groupName"?'),
      _hint(c,
          'All messages, photos and files of this group are removed from this phone.'),
      _big(c, _Big.red, 'Delete group', () => Navigator.pop(c, true),
          key: const ValueKey('delete_group_confirm')),
      _big(c, _Big.ghost, 'Cancel', () => Navigator.pop(c, false)),
    ],
  );
  return ok == true;
}

// ---------------------------------------------------------------- mock 32

/// The new name + description (null = Cancel).
class GroupEditResult {
  const GroupEditResult(this.name, this.description);
  final String name;
  final String description;
}

Future<GroupEditResult?> showEditGroupSheet(BuildContext context,
    {required String name, required String description}) {
  return showModalBottomSheet<GroupEditResult>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (c) => _EditGroupSheet(name: name, description: description),
  );
}

class _EditGroupSheet extends StatefulWidget {
  const _EditGroupSheet({required this.name, required this.description});
  final String name;
  final String description;

  @override
  State<_EditGroupSheet> createState() => _EditGroupSheetState();
}

class _EditGroupSheetState extends State<_EditGroupSheet> {
  static const int maxName = 80;
  static const int maxDesc = 300;
  late final TextEditingController _name =
      TextEditingController(text: widget.name);
  late final TextEditingController _desc =
      TextEditingController(text: widget.description);

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  InputDecoration _deco(BuildContext context, String counter, bool focused) {
    final colors = Theme.of(context).colorScheme;
    return InputDecoration(
      filled: false,
      isDense: true,
      counterText: '',
      suffixText: counter,
      suffixStyle: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
      contentPadding: const EdgeInsets.fromLTRB(2, 8, 2, 6),
      enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: colors.outlineVariant, width: 1.5)),
      focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: colors.primary, width: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final ok = _name.text.trim().isNotEmpty;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        key: const ValueKey('edit_group_sheet'),
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _title(context, 'Edit group'),
            TextField(
              key: const ValueKey('edit_group_name'),
              controller: _name,
              autofocus: true,
              maxLength: maxName,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontSize: 16),
              decoration: _deco(
                  context, '${_name.text.characters.length}/$maxName', true),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 6, 2, 14),
              child: Text('Group name',
                  style:
                      TextStyle(fontSize: 12.5, color: colors.onSurfaceVariant)),
            ),
            TextField(
              key: const ValueKey('edit_group_desc'),
              controller: _desc,
              maxLength: maxDesc,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontSize: 14.5),
              decoration: _deco(
                  context, '${_desc.text.characters.length}/$maxDesc', false),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 6, 2, 4),
              child: Text('Description',
                  style:
                      TextStyle(fontSize: 12.5, color: colors.onSurfaceVariant)),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: FilledButton(
                key: const ValueKey('edit_group_save'),
                onPressed: ok
                    ? () => Navigator.pop(context,
                        GroupEditResult(_name.text.trim(), _desc.text.trim()))
                    : null,
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(
                        fontSize: 15.5, fontWeight: FontWeight.w700)),
                child: const Text('Save'),
              ),
            ),
            _big(context, _Big.ghost, 'Cancel', () => Navigator.pop(context)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- mock 37

/// Mock 37: "Usman is not in your friends. Ali (member) is his friend."
String joinRequestHint(GroupJoinRequest r) {
  final name = r.name.trim().isEmpty ? 'This person' : r.name.trim();
  if (r.friend) return '$name is in your friends.';
  if (r.via == 'link') {
    return '$name opened the group invite link. Add only people you know.';
  }
  final via = r.viaNames;
  if (via.isEmpty) return '$name is not in your friends.';
  if (via.length == 1) {
    return '$name is not in your friends. ${via.first} (member) is his friend.';
  }
  final list = '${via.sublist(0, via.length - 1).join(', ')} and ${via.last}';
  return '$name is not in your friends. $list (members) are his friends.';
}

/// Mock 37: someone scanned the group QR. True = Add to group,
/// false = Ignore, null = closed.
Future<bool?> showJoinRequestSheet(BuildContext context, GroupJoinRequest r) {
  final name = r.name.trim().isEmpty ? 'LinkUp user' : r.name.trim();
  final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(r.atMs)));
  // Bundle G6: or "opened the invite link".
  final how = r.via == 'link' ? 'opened the invite link' : 'scanned the QR';
  final line = r.username.isEmpty
      ? '$how · $time'
      : '@${r.username} · $how · $time';
  return _sheet<bool>(
    context,
    const ValueKey('join_request_sheet'),
    (c) {
      final colors = Theme.of(c).colorScheme;
      return [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
          child: Row(
            children: [
              AccountAvatar(name: name, radius: 23, userId: r.memberId), // 214: crown
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15.5, fontWeight: FontWeight.w700)),
                    Text(line,
                        key: const ValueKey('join_request_line'),
                        style: TextStyle(
                            fontSize: 13, color: colors.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        ),
        _hint(c, joinRequestHint(r)),
        _big(c, _Big.blue, 'Add to group', () => Navigator.pop(c, true),
            key: const ValueKey('join_request_add')),
        _big(c, _Big.ghost, 'Ignore', () => Navigator.pop(c, false),
            key: const ValueKey('join_request_ignore')),
      ];
    },
  );
}
