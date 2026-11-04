import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:locallink/core/models/group.dart';
import 'package:locallink/core/presence/presence_hub.dart';
import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/core/widgets/account_avatar.dart';
import 'package:locallink/core/widgets/error_toast.dart';
import 'package:locallink/core/widgets/messenger_list_group.dart';
import 'package:locallink/features/groups/presentation/screens/group_info_screen.dart';
import 'package:locallink/features/groups/presentation/widgets/group_info_sheets.dart';

/// Bundle G1: making a group (mock 3, 3b and 4).
///
/// 3  - "New group · Add people · N of 32": your friends with a round
///      check, picked people as chips on top, arrow button bottom right.
/// 3b - no friends yet: "Go to People".
/// 4  - photo, group name, description, settings (G2), the picked
///      people, check button = Create.

/// One friend that can be added.
class GroupFriend {
  const GroupFriend({required this.deviceId, required this.name});
  final String deviceId;
  final String name;
}

/// What Create gives back: the group and the friends that could not be
/// added (today's server only knows phones that were Online once).
class GroupCreateResult {
  const GroupCreateResult(this.group, {this.skipped = const []});
  final LocalGroup group;
  final List<String> skipped;
}

/// Bundle G2 (mock 4): photo, description and settings of a new group.
class GroupCreateOptions {
  const GroupCreateOptions({
    this.photoJpeg,
    this.description = '',
    this.editInfo = 'admins',
    this.sendMessages = 'all',
    this.addMembers = 'admins',
  });
  final List<int>? photoJpeg;
  final String description;
  final String editInfo;
  final String sendMessages;
  final String addMembers;
}

typedef GroupCreateCallback = Future<GroupCreateResult> Function(
    String name, List<GroupFriend> people, GroupCreateOptions options);

/// A clear, simple reason shown to the user as is.
class GroupCreateError implements Exception {
  const GroupCreateError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Mock 3 limit (Nearby groups are up to 32).
const int kNewGroupMax = 32;

class NewGroupScreen extends StatefulWidget {
  const NewGroupScreen({
    super.key,
    required this.loadFriends,
    required this.onCreate,
    required this.onGoToPeople,
  });

  final Future<List<GroupFriend>> Function() loadFriends;
  final GroupCreateCallback onCreate;
  final VoidCallback onGoToPeople;

  @override
  State<NewGroupScreen> createState() => _NewGroupScreenState();
}

class _NewGroupScreenState extends State<NewGroupScreen> {
  List<GroupFriend>? _friends;
  final List<GroupFriend> _picked = <GroupFriend>[];
  bool _searching = false;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.loadFriends().then((list) {
      if (mounted) setState(() => _friends = list);
    }, onError: (_) {
      if (mounted) setState(() => _friends = const []);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _isPicked(GroupFriend f) => _picked.any((p) => p.deviceId == f.deviceId);

  void _toggle(GroupFriend f) {
    setState(() {
      if (_isPicked(f)) {
        _picked.removeWhere((p) => p.deviceId == f.deviceId);
      } else if (_picked.length >= kNewGroupMax) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('You can add up to $kNewGroupMax people')));
      } else {
        _picked.add(f);
      }
    });
  }

  Future<void> _next() async {
    if (_picked.isEmpty) return;
    final result = await Navigator.push<GroupCreateResult>(
      context,
      MaterialPageRoute(
        builder: (_) => NewGroupNameScreen(
          people: List<GroupFriend>.from(_picked),
          onCreate: widget.onCreate,
        ),
      ),
    );
    if (result != null && mounted) Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final friends = _friends;
    final empty = friends != null && friends.isEmpty;
    final q = _search.text.trim().toLowerCase();
    final shown = friends == null
        ? const <GroupFriend>[]
        : friends
            .where((f) => q.isEmpty || f.name.toLowerCase().contains(q))
            .toList(growable: false);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: _searching
            ? TextField(
                key: const ValueKey('new_group_search'),
                controller: _search,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Search friends',
                  filled: false,
                  border: InputBorder.none,
                ),
              )
            : NewGroupTitle(
                title: 'New group',
                subtitle: _picked.isEmpty
                    ? 'Add people'
                    : 'Add people · ${_picked.length} of $kNewGroupMax'),
        actions: [
          IconButton(
            key: const ValueKey('new_group_search_button'),
            tooltip: _searching ? 'Close search' : 'Search',
            onPressed: () => setState(() {
              _searching = !_searching;
              _search.clear();
            }),
            icon: Icon(_searching ? Icons.close : Icons.search),
          ),
        ],
      ),
      floatingActionButton: SquareGradientFab(
        key: const ValueKey('new_group_next'),
        icon: Icons.arrow_forward_rounded,
        tooltip: 'Next',
        onPressed: _picked.isEmpty ? null : _next,
      ),
      body: friends == null
          ? const Center(child: CircularProgressIndicator())
          : empty
              ? _noFriends(context)
              : ListView(
                  padding: const EdgeInsets.only(bottom: 96),
                  children: [
                    if (_picked.isNotEmpty) _chips(context),
                    const MessengerGroupLabel('Your friends', top: 10),
                    if (shown.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('No friend found',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant)),
                      )
                    else
                      ListenableBuilder(
                        listenable: PresenceHub.instance,
                        builder: (context, _) => MessengerListGroup(
                          children: [
                            for (final f in shown)
                              FriendPickRow(
                                key: ValueKey('pick_${f.deviceId}'),
                                name: f.name,
                                status: PresenceHub.instance.statusOf(f.deviceId),
                                picked: _isPicked(f),
                                onTap: () => _toggle(f),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
    );
  }

  Widget _chips(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('new_group_chips'),
      height: 86,
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(color: colors.outlineVariant.withValues(alpha: .6))),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        itemCount: _picked.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (_, i) {
          final f = _picked[i];
          return GestureDetector(
            key: ValueKey('chip_${f.deviceId}'),
            onTap: () => _toggle(f),
            child: SizedBox(
              width: 52,
              child: Column(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AccountAvatar(name: f.name, radius: 23),
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: colors.onSurfaceVariant,
                            shape: BoxShape.circle,
                            border: Border.all(color: colors.surface, width: 2),
                          ),
                          child: const Icon(Icons.close_rounded,
                              size: 10, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(f.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: colors.onSurface)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _noFriends(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 30, 24, 96),
      children: [
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
                color: colors.surfaceContainerHighest, shape: BoxShape.circle),
            child: Icon(Icons.group_outlined,
                size: 34, color: colors.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: 14),
        const Text('No friends yet',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 6),
        Text.rich(
          TextSpan(children: [
            const TextSpan(text: 'Groups are made from your friends. Add friends in '),
            const TextSpan(
                text: 'People', style: TextStyle(fontWeight: FontWeight.w700)),
            const TextSpan(text: ' first, or let them scan the group QR later.'),
          ]),
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 12.5, height: 1.4, color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const ValueKey('new_group_go_people'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          ),
          onPressed: () {
            Navigator.pop(context);
            widget.onGoToPeople();
          },
          child: const Text('Go to People',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
        ),
      ],
    );
  }
}

/// Mock 4: photo, group name, description, settings + the picked people.
class NewGroupNameScreen extends StatefulWidget {
  const NewGroupNameScreen({
    super.key,
    required this.people,
    required this.onCreate,
  });

  final List<GroupFriend> people;
  final GroupCreateCallback onCreate;

  @override
  State<NewGroupNameScreen> createState() => _NewGroupNameScreenState();
}

class _NewGroupNameScreenState extends State<NewGroupNameScreen> {
  static const int maxName = 80;
  static const int maxDesc = 300;
  final _name = TextEditingController();
  final _desc = TextEditingController();
  bool _busy = false;

  /// Bundle G2 (mock 4 + 5 + 33).
  List<int>? _photo;
  String _editInfo = 'admins';
  String _sendMessages = 'all';
  String _addMembers = 'admins';

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final pick = await showGroupPhotoSheet(context, hasPhoto: _photo != null);
    if (pick == null || !mounted) return;
    setState(() => _photo = pick.remove ? null : pick.bytes);
  }

  Future<void> _settings() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => GroupSettingsScreen(
          groupName: _name.text.trim().isEmpty ? 'New group' : _name.text.trim(),
          editInfo: _editInfo,
          sendMessages: _sendMessages,
          addMembers: _addMembers,
          onChange: (field, value) async {
            setState(() {
              switch (field) {
                case 'edit_info':
                  _editInfo = value;
                case 'send_messages':
                  _sendMessages = value;
                case 'add_members':
                  _addMembers = value;
              }
            });
          },
        ),
      ),
    );
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final result = await widget.onCreate(
        name,
        widget.people,
        GroupCreateOptions(
          photoJpeg: _photo,
          description: _desc.text.trim(),
          editInfo: _editInfo,
          sendMessages: _sendMessages,
          addMembers: _addMembers,
        ),
      );
      if (mounted) Navigator.pop(context, result);
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      if (error is GroupCreateError) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      } else {
        showErrorToast(context, error: error);
      }
    }
  }

  Widget _photoCircle(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final photo = _photo;
    return Center(
      child: GestureDetector(
        key: const ValueKey('new_group_photo'),
        onTap: _busy ? null : _pickPhoto,
        child: SizedBox(
          width: 88,
          height: 88,
          child: Stack(
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest, shape: BoxShape.circle),
                clipBehavior: Clip.antiAlias,
                child: photo == null
                    ? Icon(Icons.photo_camera_outlined,
                        size: 34, color: colors.onSurfaceVariant)
                    : Image.memory(Uint8List.fromList(photo),
                        key: const ValueKey('new_group_photo_image'),
                        fit: BoxFit.cover),
              ),
              Positioned(
                right: 2,
                bottom: 2,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    gradient: LocalLinkBrand.linearGradient,
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.surface, width: 2),
                  ),
                  child: const Icon(Icons.add_rounded,
                      size: 16, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final ready = _name.text.trim().isNotEmpty && !_busy;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title:
            const NewGroupTitle(title: 'New group', subtitle: 'Name and photo'),
      ),
      floatingActionButton: SquareGradientFab(
        key: const ValueKey('new_group_create'),
        icon: Icons.check_rounded,
        tooltip: 'Create group',
        busy: _busy,
        onPressed: ready ? _create : null,
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 18, bottom: 96),
        children: [
          _photoCircle(context),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            child: Text('Add group photo (optional)',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: colors.onSurfaceVariant)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              key: const ValueKey('new_group_name'),
              controller: _name,
              autofocus: true,
              maxLength: maxName,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _create(),
              style: const TextStyle(fontSize: 16),
              decoration: InputDecoration(
                filled: false,
                isDense: true,
                counterText: '',
                suffixText: '${_name.text.characters.length}/$maxName',
                suffixStyle:
                    TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
                contentPadding: const EdgeInsets.fromLTRB(2, 8, 2, 6),
                enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: colors.primary, width: 2)),
                focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: colors.primary, width: 2)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
            child: Text('Group name',
                style: TextStyle(fontSize: 12.5, color: colors.onSurfaceVariant)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: TextField(
              key: const ValueKey('new_group_description'),
              controller: _desc,
              maxLength: maxDesc,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(fontSize: 15),
              decoration: InputDecoration(
                filled: false,
                isDense: true,
                counterText: '',
                hintText: 'Description (optional)',
                hintStyle: TextStyle(color: colors.onSurfaceVariant),
                contentPadding: const EdgeInsets.fromLTRB(2, 8, 2, 6),
                enabledBorder: UnderlineInputBorder(
                    borderSide:
                        BorderSide(color: colors.outlineVariant, width: 1.5)),
                focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: colors.primary, width: 2)),
              ),
            ),
          ),
          const MessengerGroupLabel('Settings', top: 18),
          MessengerListGroup(
            dividerIndent: 58,
            children: [
              InkWell(
                key: const ValueKey('new_group_settings'),
                onTap: _busy ? null : _settings,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                  child: Row(
                    children: [
                      Icon(Icons.settings_outlined,
                          size: 22, color: colors.onSurfaceVariant),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Group settings',
                                style: TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 1),
                            Text(
                                groupSettingsLine(
                                    LocalGroup(
                                        id: '',
                                        name: '',
                                        ownerId: '',
                                        createdAt: '',
                                        editInfo: _editInfo,
                                        sendMessages: _sendMessages,
                                        addMembers: _addMembers),
                                    both: true),
                                key: const ValueKey('new_group_settings_line'),
                                style: TextStyle(
                                    fontSize: 12.5,
                                    color: colors.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right,
                          size: 20, color: colors.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
            ],
          ),
          MessengerGroupLabel(
              '${widget.people.length} ${widget.people.length == 1 ? 'person' : 'people'} + you',
              top: 16),
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
              itemCount: widget.people.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (_, i) {
                final f = widget.people[i];
                return SizedBox(
                  width: 52,
                  child: Column(
                    children: [
                      AccountAvatar(name: f.name, radius: 20),
                      const SizedBox(height: 4),
                      Text(f.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11.5, color: colors.onSurface)),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Two-line title: "New group" + small grey line.
class NewGroupTitle extends StatelessWidget {
  const NewGroupTitle({super.key, required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
        Text(subtitle,
            key: const ValueKey('new_group_subtitle'),
            style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

/// One friend row: photo, name, status dot + Nearby / Online / Offline,
/// round check on the right.
class FriendPickRow extends StatelessWidget {
  const FriendPickRow({
    super.key,
    required this.name,
    required this.status,
    required this.picked,
    required this.onTap,
    this.note,
    this.enabled = true,
  });

  final String name;
  final PresenceStatus status;
  final bool picked;
  final VoidCallback onTap;

  /// Bundle G2 (mock 35): grey line instead of the status
  /// ("Already in the group"); with [enabled] false the row is dim.
  final String? note;
  final bool enabled;

  static const Color nearbyGreen = Color(0xFF1FB57A);
  static const Color offlineGrey = Color(0xFFB9BAC2);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dot = switch (status) {
      PresenceStatus.nearby => nearbyGreen,
      PresenceStatus.online => colors.primary,
      PresenceStatus.offline => offlineGrey,
    };
    final row = InkWell(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            AccountAvatar(name: name, radius: 21),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  if (note != null)
                    Text(note!,
                        style: TextStyle(
                            fontSize: 12.5, color: colors.onSurfaceVariant))
                  else
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration:
                              BoxDecoration(color: dot, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 5),
                        Text(status.label,
                            style: TextStyle(
                                fontSize: 12.5, color: colors.onSurfaceVariant)),
                      ],
                    ),
                ],
              ),
            ),
            if (enabled) PickCheck(picked: picked),
          ],
        ),
      ),
    );
    return enabled ? row : Opacity(opacity: .5, child: row);
  }
}

/// Round check: empty grey ring / filled blue with a white tick.
class PickCheck extends StatelessWidget {
  const PickCheck({super.key, required this.picked});
  final bool picked;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: ValueKey(picked ? 'pick_on' : 'pick_off'),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: picked ? colors.primary : null,
        border: Border.all(
            color: picked ? colors.primary : colors.outline, width: 2),
      ),
      child: picked
          ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
          : null,
    );
  }
}

/// Mock .fab2: rounded square (corners 18), blue->cyan, white icon; grey
/// and not tappable when [onPressed] is null.
class SquareGradientFab extends StatelessWidget {
  const SquareGradientFab({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.busy = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool busy;

  static const Color offGrey = Color(0xFFD7D8DF);

  @override
  Widget build(BuildContext context) {
    final on = onPressed != null || busy;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        elevation: on ? 4 : 0,
        shadowColor: const Color(0x591E5BFF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: busy ? null : onPressed,
          child: Ink(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: on ? LocalLinkBrand.linearGradient : null,
              color: on ? null : offGrey,
            ),
            child: Center(
              child: busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.4, color: Colors.white))
                  : Icon(icon, color: Colors.white, size: 26),
            ),
          ),
        ),
      ),
    );
  }
}
