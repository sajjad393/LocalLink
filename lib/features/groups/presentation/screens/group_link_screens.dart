import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'package:locallink/core/models/group.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/core/services/locallink_api.dart'
    show GroupActionException;
import 'package:locallink/core/widgets/account_avatar.dart';
import 'package:locallink/core/widgets/error_toast.dart';
import 'package:locallink/core/widgets/group_avatar.dart';
import 'package:locallink/core/widgets/messenger_list_group.dart';
import 'package:locallink/features/groups/data/group_change_hub.dart';
import 'package:locallink/features/groups/data/group_invite_link.dart';
import 'package:locallink/features/groups/presentation/screens/new_group_screen.dart'
    show NewGroupTitle;

/// Bundle G6: invite link screens (mock L2 / L3 / L4 / L5).

// ---------------------------------------------------------------- L2 + L5

class GroupInviteLinkScreen extends StatefulWidget {
  const GroupInviteLinkScreen({super.key, required this.group});

  final LocalGroup group;

  @override
  State<GroupInviteLinkScreen> createState() => _GroupInviteLinkScreenState();
}

class _GroupInviteLinkScreenState extends State<GroupInviteLinkScreen> {
  String _token = '';
  bool _busy = false;

  LocalGroup get _g => widget.group;

  @override
  void initState() {
    super.initState();
    if (!_g.nearbyOnly) unawaited(_load(false));
  }

  Future<void> _load(bool reset) async {
    final s = GroupInviteService.instance;
    if (s == null || _busy) return;
    setState(() => _busy = true);
    try {
      final t = await s.token(_g, reset: reset);
      if (mounted) setState(() => _token = t);
      if (reset && mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(content: Text('New link made. The old one stops working.')));
      }
    } catch (error) {
      if (mounted) showErrorToast(context, error: error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: GroupInviteLink.link(_token)));
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(const SnackBar(content: Text('Link copied')));
  }

  Future<void> _share() async {
    try {
      final base = GroupInviteService.instance?.serverBase ?? '';
      await Share.share(GroupInviteLink.shareText(_g.name, _token, base));
    } catch (error) {
      AppLogger.error('GROUP_LINK_SHARE_FAILED', error: error);
    }
  }

  Future<void> _reset() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Reset link?'),
        content: const Text('The old link stops working. People who have it '
            "can't use it to join."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          TextButton(
              key: const ValueKey('link_reset_yes'),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Reset link')),
        ],
      ),
    );
    if (yes == true) await _load(true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hint =
        TextStyle(fontSize: 13, height: 1.4, color: colors.onSurfaceVariant);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: NewGroupTitle(title: 'Invite with link', subtitle: _g.name),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const SizedBox(height: 18),
          Center(
            child: GroupAvatar(
                radius: 42, groupId: _g.id, photoVersion: _g.photoVersion),
          ),
          const SizedBox(height: 10),
          Text(_g.name,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
          if (_g.nearbyOnly)
            // L5
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
              child: Text.rich(
                const TextSpan(children: [
                  TextSpan(
                      text: 'This group works only Nearby (it is not on the '
                          "server yet), so a link can't work. Use "),
                  TextSpan(
                      text: 'Invite with QR',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: ', or wait until a member is Online once.'),
                ]),
                key: const ValueKey('link_nearby_only'),
                textAlign: TextAlign.center,
                style: hint,
              ),
            )
          else ...[
            Container(
              key: const ValueKey('link_box'),
              margin: const EdgeInsets.fromLTRB(18, 16, 18, 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF3FF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(Icons.link_rounded,
                      color: Color(0xFF1E4FE0), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _token.isEmpty
                        ? const Align(
                            alignment: Alignment.centerLeft,
                            child: SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2)))
                        : Text(GroupInviteLink.link(_token),
                            key: const ValueKey('link_text'),
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1E4FE0))),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
              child: Text(
                  'Anyone with LinkUp who opens this link can ask to join, '
                  'from anywhere. It needs internet (the server). With '
                  '"Approve new members" on, an admin must say yes.',
                  style: hint),
            ),
            MessengerListGroup(
              dividerIndent: 58,
              children: [
                _LinkRow(
                  key: const ValueKey('link_copy'),
                  icon: Icons.copy_rounded,
                  title: 'Copy link',
                  subtitle: 'Paste it in any app',
                  onTap: _token.isEmpty ? null : _copy,
                ),
                _LinkRow(
                  key: const ValueKey('link_share'),
                  icon: Icons.share_outlined,
                  title: 'Share link',
                  subtitle: 'WhatsApp, SMS, email…',
                  onTap: _token.isEmpty ? null : _share,
                ),
                _LinkRow(
                  key: const ValueKey('link_reset'),
                  icon: Icons.restart_alt_rounded,
                  title: 'Reset link',
                  subtitle: 'The old link stops working',
                  red: true,
                  onTap: _busy || _token.isEmpty ? null : _reset,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.red = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool red;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fg = red ? colors.error : colors.onSurface;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            Icon(icon,
                size: 22, color: red ? colors.error : colors.onSurfaceVariant),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700, color: fg)),
                  const SizedBox(height: 1),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 12.5, color: colors.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- L4

/// Opening an invite link: Join group / Ask to join -> Requested ✓.
class JoinGroupByLinkScreen extends StatefulWidget {
  const JoinGroupByLinkScreen({super.key, required this.token});

  final String token;

  @override
  State<JoinGroupByLinkScreen> createState() => _JoinGroupByLinkScreenState();
}

class _JoinGroupByLinkScreenState extends State<JoinGroupByLinkScreen> {
  GroupJoinPreview? _p;
  String _error = '';
  bool _busy = false;
  StreamSubscription<String>? _changes;

  @override
  void initState() {
    super.initState();
    _p = GroupInviteService.instance?.cached(widget.token);
    unawaited(_load());
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final s = GroupInviteService.instance;
    if (s == null) {
      setState(() => _error = 'Sign in to the server to open group links.');
      return;
    }
    try {
      final p = await s.preview(widget.token, fresh: true);
      if (!mounted) return;
      setState(() {
        _p = p;
        _error = '';
      });
      _changes ??= GroupChangeHub.instance.changes.listen((id) {
        if (id == p.groupId && _p?.status == 'requested') unawaited(_load());
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = friendlyLinkError(error));
    }
  }

  Future<void> _join() async {
    final s = GroupInviteService.instance;
    final p = _p;
    if (s == null || p == null || _busy) return;
    setState(() => _busy = true);
    try {
      final status = await s.join(widget.token);
      if (!mounted) return;
      if (status == 'joined' || status == 'member') {
        await _open(p.groupId);
        return;
      }
      setState(() => _p = p.withStatus(status));
    } catch (error) {
      if (mounted) showErrorToast(context, error: error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(String gid) async {
    final open = GroupInviteService.openGroup;
    final nav = Navigator.of(context);
    if (open == null) {
      nav.maybePop();
      return;
    }
    nav.pop();
    await open(gid);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hint =
        TextStyle(fontSize: 13, height: 1.4, color: colors.onSurfaceVariant);
    final p = _p;
    final big = FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(48),
      shape: const StadiumBorder(),
      textStyle: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
    );
    final ghost = OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(48),
      shape: const StadiumBorder(),
      side: BorderSide(color: colors.outlineVariant),
      foregroundColor: colors.onSurface,
      disabledForegroundColor: colors.onSurface,
      textStyle: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
    );
    return Scaffold(
      appBar: AppBar(titleSpacing: 0, title: const Text('Join group')),
      body: ListView(
        padding: const EdgeInsets.only(top: 30, bottom: 24),
        children: [
          const Center(child: GroupAvatar(radius: 48)),
          const SizedBox(height: 12),
          if (p == null && _error.isEmpty)
            const Center(
                child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator())),
          if (p == null && _error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: Text(_error,
                  key: const ValueKey('join_link_error'),
                  textAlign: TextAlign.center,
                  style: hint.copyWith(color: colors.error)),
            ),
          if (p != null) ...[
            Text(p.name,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            Text(p.line,
                key: const ValueKey('join_link_line'),
                textAlign: TextAlign.center,
                style: hint),
            const SizedBox(height: 10),
            if (p.memberNames.isNotEmpty) _Faces(names: p.memberNames),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  switch (p.status) {
                    'member' => FilledButton(
                        key: const ValueKey('join_link_open'),
                        onPressed: () => _open(p.groupId),
                        style: big,
                        child: const Text('Open group'),
                      ),
                    'requested' => Opacity(
                        opacity: .9,
                        child: OutlinedButton(
                          key: const ValueKey('join_link_requested'),
                          onPressed: null,
                          style: ghost,
                          child: const Text('Requested ✓'),
                        ),
                      ),
                    _ => FilledButton(
                        key: const ValueKey('join_link_join'),
                        onPressed: _busy ? null : _join,
                        style: big,
                        child: Text(p.approve ? 'Ask to join' : 'Join group'),
                      ),
                  },
                  const SizedBox(height: 10),
                  if (p.status == 'requested')
                    Text(
                        'An admin must say yes. This stays for 24 hours. '
                        'The group opens in your Chats when it is done.',
                        textAlign: TextAlign.center,
                        style: hint)
                  else if (p.status != 'member')
                    OutlinedButton(
                      key: const ValueKey('join_link_not_now'),
                      onPressed: () => Navigator.of(context).maybePop(),
                      style: ghost,
                      child: const Text('Not now'),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Faces extends StatelessWidget {
  const _Faces({required this.names});
  final List<String> names;

  @override
  Widget build(BuildContext context) => Center(
        child: SizedBox(
          height: 38,
          width: 38.0 + (names.length - 1) * 26,
          child: Stack(
            children: [
              for (var i = 0; i < names.length; i++)
                Positioned(
                  left: i * 26.0,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          width: 2),
                    ),
                    child: AccountAvatar(name: names[i], radius: 17),
                  ),
                ),
            ],
          ),
        ),
      );
}

String friendlyLinkError(Object error) {
  if (error is GroupActionException && error.code == 'GROUP_LINK_INVALID') {
    return "This invite link doesn't work any more. Ask for a new one.";
  }
  return "Can't open the link now. Check the internet and try again.";
}

// ---------------------------------------------------------------- L3

/// The invite card in a chat bubble (fixed width: goes in the media slot).
class GroupInviteCard extends StatefulWidget {
  const GroupInviteCard({super.key, required this.token});

  final String token;

  @override
  State<GroupInviteCard> createState() => _GroupInviteCardState();
}

class _GroupInviteCardState extends State<GroupInviteCard> {
  GroupJoinPreview? _p;

  @override
  void initState() {
    super.initState();
    final s = GroupInviteService.instance;
    _p = s?.cached(widget.token);
    if (s != null && _p == null) {
      unawaited(s.preview(widget.token).then((p) {
        if (mounted) setState(() => _p = p);
      }).catchError((Object _) {}));
    }
  }

  void _open() {
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => JoinGroupByLinkScreen(token: widget.token)));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final p = _p;
    final sub = p == null
        ? 'Group invite'
        : 'Group invite · ${p.members} ${p.members == 1 ? 'member' : 'members'}';
    return SizedBox(
      width: 250,
      child: Material(
        color: colors.surface.withValues(alpha: .7),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          key: ValueKey('invite_card_${widget.token}'),
          borderRadius: BorderRadius.circular(12),
          onTap: _open,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            child: Row(
              children: [
                const GroupAvatar(radius: 19),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p?.name ?? 'Group',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700)),
                      Text(sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12, color: colors.onSurfaceVariant)),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E5BFF),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(p?.status == 'member' ? 'Open' : 'Join',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
