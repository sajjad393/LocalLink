import 'dart:async';

import 'package:flutter/material.dart';

import 'package:locallink/features/share_app/presentation/share_app_entry.dart';
import 'package:locallink/core/widgets/messenger_conversation_tile.dart' show PresenceAvatar;
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/core/widgets/account_avatar.dart';
import 'package:locallink/core/widgets/local_link_state_view.dart';
import 'package:locallink/core/presence/presence_hub.dart';
import 'package:locallink/core/widgets/presence_way.dart';
import 'package:locallink/core/presence/block_hub.dart';
import 'package:locallink/features/directory/data/friend_requests.dart';
import 'package:locallink/features/directory/presentation/contact_sheets.dart';
import 'package:locallink/core/widgets/messenger_list_group.dart';
import 'package:locallink/core/widgets/tab_top_bar.dart';
import 'package:locallink/core/widgets/brand_gradient_fab.dart';
import 'package:locallink/core/widgets/movable_fab.dart';
import 'package:locallink/features/calls/bloc/call_bloc.dart';
import 'package:locallink/features/calls/presentation/screens/call_screen.dart';
import 'package:locallink/features/connectivity/bloc/connectivity_bloc.dart';
import 'package:locallink/features/connectivity/bloc/mesh_bloc.dart';
import 'package:locallink/features/directory/bloc/contacts_bloc.dart';
import 'package:locallink/features/directory/domain/directory_models.dart';
import 'package:locallink/features/directory/data/services/pairing_service.dart';
import 'package:locallink/features/directory/domain/directory_repository_contract.dart';
import 'package:locallink/features/directory/presentation/add_contact_screen.dart';
import 'package:locallink/features/files/domain/file_transfer_repository_contract.dart';
import 'package:locallink/features/messaging/bloc/chat_bloc.dart';
import 'package:locallink/features/messaging/domain/messaging_repository_contract.dart';
import 'package:locallink/features/messaging/presentation/screens/chat_screen.dart';
import 'package:locallink/core/notifications/local_link_notification_service.dart';

/// Bundle 183 (N3): the People filter (sliders button).
enum PeopleFilter { all, nearby, online }

class ContactsScreen extends StatefulWidget {
  final DirectoryRepositoryContract directory;

  /// Bundle 108: hands the Nearby screen the local pairing engine.
  final PairingService pairing;
  final ConnectivityBloc connectivity;
  final MeshBloc mesh;
  final MessagingRepositoryContract messaging;
  final FileTransferRepositoryContract files;
  final CallBloc calls;
  final IdentityCryptoService crypto;
  final LocalLinkNotificationService notifications;

  /// Bundle 170: this account's user id ("This is you" on your profile,
  /// your own phones hidden from Nearby).
  final String selfUserId;

  /// Bundle 210: my name for the Share LinkUp page ("Shared by …").
  final String shareOwnerName;

  const ContactsScreen({
    required this.pairing,
    super.key,
    required this.directory,
    required this.connectivity,
    required this.mesh,
    required this.messaging,
    required this.files,
    required this.calls,
    required this.crypto,
    required this.notifications,
    this.selfUserId = '',
    this.shareOwnerName = '',
  });

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  late final ContactsBloc bloc;
  final _searchController = TextEditingController();
  String _query = '';
  // Bundle 183 (N11): not remembered - starts at All every time.
  PeopleFilter _filter = PeopleFilter.all;

  @override
  void initState() {
    super.initState();
    bloc = ContactsBloc(widget.directory)..load();
    // Bundle 196: block / unblock / add back anywhere -> list again.
    BlockHub.instance.addListener(_onBlockChange);
  }

  void _onBlockChange() => unawaited(bloc.load());

  Device _device(DirectoryProfile p) => Device(
        id: p.deviceId,
        name: p.displayName.isEmpty ? p.username : p.displayName,
        platform: 'android',
        createdAt: '',
        lastSeenAt: '',
        status: 'active',
        networkStatus: DeviceNetworkStatus.wifiDirect,
        current: false,
      );

  Future<void> _chat(DirectoryProfile p) async {
    if (p.deviceId.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This person is not currently available.')));
      return;
    }
    final device = _device(p);
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          controller: ChatBloc(repository: widget.messaging, device: device),
          files: widget.files,
          notifications: widget.notifications,
          onStartCall: (_) async {
            await widget.calls.startCall(device);
            final session = widget.calls.session;
            if (session == null || !mounted) return;
            await Navigator.push<void>(this.context, MaterialPageRoute(builder: (_) => CallScreen(controller: widget.calls, initialSession: session)));
          },
        ),
      ),
    );
  }

  Future<void> _addContact() async {
    await Navigator.push<void>(
      context,
      // Bundle 170: Nearby lives inside Add Contact now.
      MaterialPageRoute(builder: (_) => AddContactScreen(
        repository: widget.directory,
        crypto: widget.crypto,
        onStartChat: _chat,
        connectivity: widget.connectivity,
        mesh: widget.mesh,
        pairing: widget.pairing,
        selfUserId: widget.selfUserId,
      )),
    );
    await bloc.load();
  }

  @override
  void dispose() {
    BlockHub.instance.removeListener(_onBlockChange);
    _searchController.dispose();
    bloc.close();
    super.dispose();
  }

  /// Bundle 183 (N7): the person's live status, the same one the avatar dot
  /// shows. No linked phone = Offline.
  PresenceStatus _statusOf(DirectoryProfile p) => p.deviceId.isEmpty
      ? PresenceStatus.offline
      : PresenceHub.instance.statusOf(p.deviceId);

  bool _passesFilter(DirectoryProfile p) => switch (_filter) {
        PeopleFilter.all => true,
        PeopleFilter.nearby => _statusOf(p) == PresenceStatus.nearby,
        PeopleFilter.online => _statusOf(p) == PresenceStatus.online,
      };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      // Bundle 183 (L/N1): the shared tab top bar, "People" like the tab,
      // no back arrow.
      appBar: const TabTopBar(title: Text('People')),
      // Bundle 206: the round button can be moved (one place for Chats,
      // Calls and People). Same look, now the shared BrandGradientFab.
      body: MovableFabArea(
        label: 'Add contact',
        fab: BrandGradientFab(
          heroTag: 'add_contact_fab',
          tooltip: 'Add contact',
          icon: Icons.add,
          onPressed: _addContact,
        ),
        child: StreamBuilder<List<DirectoryProfile>>(
        stream: bloc.stream,
        initialData: bloc.state,
        builder: (context, snapshot) => ListenableBuilder(
          // Bundle 183 (N8): the filtered list follows status changes live.
          // Bundle 196: blocked people + friend requests change it too.
          listenable: Listenable.merge([
            PresenceHub.instance,
            BlockHub.instance,
            FriendRequestBook.instance,
          ]),
          builder: (context, _) {
          final all = snapshot.data ?? const <DirectoryProfile>[];
          final query = _query.trim().toLowerCase();
          final searched = query.isEmpty
              ? all
              : all.where((profile) {
                  final title = profile.displayName.isEmpty ? profile.username : profile.displayName;
                  return title.toLowerCase().contains(query) || profile.username.toLowerCase().contains(query);
                }).toList();
          // Bundle 183 (N9): search and filter together.
          final contacts = searched.where(_passesFilter).toList();
          final filtered = _filter != PeopleFilter.all;
          // Bundle 196 (4.3/4.4): BLOCKED part - All only, follows search.
          final blocked = filtered
              ? const <BlockedPerson>[]
              : BlockHub.instance.people.where((p) {
                  if (query.isEmpty) return true;
                  return p.label.toLowerCase().contains(query) ||
                      p.username.toLowerCase().contains(query);
                }).toList();
          // Bundle 196 (12b.5): REQUESTS part at the top (every filter).
          final requests = FriendRequestBook.instance.visible;

          return RefreshIndicator(
            onRefresh: bloc.load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: LocalLinkSpacing.xxl),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(LocalLinkSpacing.lg, LocalLinkSpacing.md, LocalLinkSpacing.lg, 0),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                    decoration: InputDecoration(
                      hintText: 'Search people',
                      prefixIcon: const Icon(Icons.search),
                      // Bundle 183 (N3/N4): the sliders icon is a real
                      // button now - All / Nearby / Online.
                      suffixIcon: _filterButton(colors),
                    ),
                  ),
                ),
                if (filtered)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _filterChip(colors),
                    ),
                  ),
                // Bundle 210: give LinkUp to a nearby phone (hidden while
                // searching).
                if (query.isEmpty)
                  InviteNearbyCard(ownerName: widget.shareOwnerName),
                if (requests.isNotEmpty) ...[
                  MessengerGroupLabel('Requests',
                      key: const ValueKey('people_requests_label'),
                      top: filtered ? 16 : 24),
                  _requestGroup(context, requests),
                ],
                // Bundle 183 (O/N12): the shared small grey CAPITALS title.
                MessengerGroupLabel('Your contacts', top: filtered ? 16 : 24),
                if (all.isEmpty || (contacts.isEmpty && query.isNotEmpty))
                  SizedBox(
                    height: 420,
                    child: LocalLinkEmptyView(
                      icon: Icons.people_outline,
                      lottieAsset: 'assets/animations/empty_inbox.json',
                      title: query.isEmpty ? 'No contacts yet' : 'No people found',
                      message: query.isEmpty ? 'Add a contact or discover nearby LinkUp phones.' : 'Try another name or username.',
                      actionLabel: query.isEmpty ? 'Add contact' : null,
                      onAction: query.isEmpty ? _addContact : null,
                    ),
                  )
                else if (contacts.isEmpty)
                  // Bundle 183 (N10): filter on, nobody matches.
                  MessengerListGroup(children: [
                    SizedBox(
                      key: const ValueKey('people_filter_empty'),
                      height: 60,
                      child: Center(
                        child: Text(
                          _filter == PeopleFilter.nearby
                              ? 'No one nearby right now'
                              : 'No one online right now',
                          style: TextStyle(
                              fontSize: 14, color: colors.onSurfaceVariant),
                        ),
                      ),
                    ),
                  ])
                else
                  _contactGroup(context, contacts),
                if (blocked.isNotEmpty) ...[
                  MessengerGroupLabel('Blocked',
                      key: const ValueKey('people_blocked_label'),
                      color: colors.error),
                  _blockedGroup(context, blocked),
                ],
              ],
            ),
          );
          },
        ),
      ),
      ),
    );
  }

  static String _filterLabel(PeopleFilter f) => switch (f) {
        PeopleFilter.all => 'All',
        PeopleFilter.nearby => 'Nearby',
        PeopleFilter.online => 'Online',
      };

  Widget _filterButton(ColorScheme colors) {
    return PopupMenuButton<PeopleFilter>(
      key: const ValueKey('people_filter_button'),
      tooltip: 'Filter',
      position: PopupMenuPosition.under,
      constraints: const BoxConstraints.tightFor(width: 180),
      color: colors.surfaceContainerLowest,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      icon: Icon(
        Icons.tune_outlined,
        color: _filter == PeopleFilter.all
            ? colors.onSurfaceVariant
            : colors.primary,
      ),
      onSelected: (f) => setState(() => _filter = f),
      itemBuilder: (_) => [
        for (final f in PeopleFilter.values)
          PopupMenuItem<PeopleFilter>(
            key: ValueKey('people_filter_${f.name}'),
            value: f,
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _filterLabel(f),
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: colors.onSurface),
                  ),
                ),
                if (f == _filter)
                  Icon(Icons.check,
                      key: const ValueKey('people_filter_tick'),
                      size: 24,
                      color: colors.primary),
              ],
            ),
          ),
      ],
    );
  }

  /// "Nearby ×" / "Online ×" - tap it (or the ×) to go back to All.
  Widget _filterChip(ColorScheme colors) {
    return Material(
      key: const ValueKey('people_filter_chip'),
      color: colors.primaryContainer,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => setState(() => _filter = PeopleFilter.all),
        child: SizedBox(
          height: 32,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 12),
              Text(
                _filterLabel(_filter),
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: colors.onPrimaryContainer),
              ),
              const SizedBox(width: 6),
              Icon(Icons.close,
                  key: const ValueKey('people_filter_clear'),
                  size: 18,
                  color: colors.onPrimaryContainer),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// Contact rows in the shared Settings-style grey card (183, O).
  Widget _contactGroup(BuildContext context, List<DirectoryProfile> contacts) {
    final tiles = <Widget>[];
    for (var i = 0; i < contacts.length; i++) {
      final profile = contacts[i];
      final title =
          profile.displayName.isEmpty ? profile.username : profile.displayName;
      tiles.add(
        ListTile(
          minVerticalPadding: LocalLinkSpacing.sm,
          // Bundle 148: same live status badge as Chats / Calls.
          leading: profile.deviceId.isEmpty
              ? AccountAvatar(name: title, radius: 24, peerId: profile.userId)
              : PresenceAvatar(
                  avatar: AccountAvatar(name: title, radius: 24, peerId: profile.userId),
                  device: _device(profile),
                ),
          title: Text(title, style: Theme.of(context).textTheme.titleSmall),
          // Bundle 196 (4.2): "Private" when they made their own profile
          // private (their signed profile says so).
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text('@${profile.username}',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  if (!profile.discoverableByName) ...[
                    const SizedBox(width: 6),
                    PrivatePill(
                        key: ValueKey('people_private_${profile.userId}')),
                  ],
                ],
              ),
              // Bundle 201 (F, mock ST S4): how they are reached.
              if (profile.deviceId.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: PresenceWayLine(
                    deviceId: profile.deviceId,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 12.5,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
            ],
          ),
          // Bundle 196 (4.1): ⋮ opens the actions sheet (no pop-up menu).
          trailing: IconButton(
            key: ValueKey('people_more_${profile.userId}'),
            tooltip: 'More',
            icon: const Icon(Icons.more_vert),
            onPressed: () => _actions(profile),
          ),
          onTap: () => _chat(profile),
          onLongPress: () => _actions(profile),
        ),
      );
    }
    return MessengerListGroup(children: tiles);
  }

  static String _titleOf(DirectoryProfile p) =>
      p.displayName.isEmpty ? p.username : p.displayName;

  /// Bundle 196 (5): Message / Voice call / Remove contact / Block.
  Future<void> _actions(DirectoryProfile profile) async {
    final name = _titleOf(profile);
    final choice = await showContactActionsSheet(context,
        name: name, username: profile.username, userId: profile.userId);
    if (!mounted || choice == null) return;
    switch (choice) {
      case ContactSheetChoice.message:
        await _chat(profile);
      case ContactSheetChoice.call:
        await _call(profile);
      case ContactSheetChoice.remove:
        await runRemoveFlow(context,
            userId: profile.userId,
            name: name,
            username: profile.username,
            remove: bloc.remove);
      case ContactSheetChoice.block:
        await runBlockFlow(context,
            userId: profile.userId,
            name: name,
            username: profile.username,
            from: 'people',
            block: bloc.block);
    }
  }

  /// Bundle 196 (5.1): the same call as the chat's call button.
  Future<void> _call(DirectoryProfile p) async {
    if (p.deviceId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('This person is not currently available.')));
      return;
    }
    final device = _device(p);
    await widget.calls.startCall(device);
    final session = widget.calls.session;
    if (session == null || !mounted) return;
    await Navigator.push<void>(
        context,
        MaterialPageRoute(
            builder: (_) =>
                CallScreen(controller: widget.calls, initialSession: session)));
  }

  /// Bundle 196 (4.3): the red BLOCKED part (tap or ⋮ = Unblock sheet).
  Widget _blockedGroup(BuildContext context, List<BlockedPerson> people) {
    final colors = Theme.of(context).colorScheme;
    return MessengerListGroup(children: [
      for (final p in people)
        ListTile(
          key: ValueKey('people_blocked_row_${p.userId}'),
          minVerticalPadding: LocalLinkSpacing.sm,
          leading: MutedAvatar(name: p.label, radius: 24),
          title: Text(p.label,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(color: colors.onSurfaceVariant)),
          subtitle: Align(
            alignment: Alignment.centerLeft,
            child: BlockedUserLine(username: p.username),
          ),
          trailing: IconButton(
            tooltip: 'More',
            icon: const Icon(Icons.more_vert),
            onPressed: () => runUnblockFlow(context, p, from: 'people'),
          ),
          onTap: () => runUnblockFlow(context, p, from: 'people'),
        ),
    ]);
  }

  /// Bundle 196 (12b.5): people near me who asked to add me (I am private).
  Widget _requestGroup(BuildContext context, List<FriendRequest> requests) {
    final colors = Theme.of(context).colorScheme;
    final now = FriendRequestBook.instance.now();
    return MessengerListGroup(children: [
      for (final r in requests)
        Padding(
          key: ValueKey('people_request_${r.deviceId}'),
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AccountAvatar(name: r.name, radius: 24, userId: r.deviceId), // 214: crown
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall),
                    Text(
                      '${r.username.isEmpty ? '' : '@${r.username} · '}'
                      'wants to add you · ${FriendRequestRules.age(r.atMs, now)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13,
                          color: colors.onSurfaceVariant,
                          letterSpacing: 0),
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      children: [
                        TextButton(
                          key: ValueKey('request_decline_${r.deviceId}'),
                          onPressed: () => _declineRequest(r),
                          child: const Text('Decline'),
                        ),
                        FilledButton.tonal(
                          key: ValueKey('request_accept_${r.deviceId}'),
                          onPressed: () => _acceptRequest(r),
                          child: const Text('Accept'),
                        ),
                      ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
    ]);
  }

  Future<void> _acceptRequest(FriendRequest r) async {
    final messenger = ScaffoldMessenger.of(context);
    final accept = FriendRequestBook.instance.onAccept;
    if (accept == null) return;
    try {
      await accept(r.deviceId);
      await bloc.load();
      messenger.showSnackBar(SnackBar(content: Text('${r.name} added')));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Could not add ${r.name}. Try again.')));
    }
  }

  Future<void> _declineRequest(FriendRequest r) async {
    final messenger = ScaffoldMessenger.of(context);
    final decline = FriendRequestBook.instance.onDecline;
    try {
      if (decline != null) {
        await decline(r.deviceId);
      } else {
        await FriendRequestBook.instance.decline(r.deviceId);
      }
      messenger
          .showSnackBar(const SnackBar(content: Text('Request declined')));
    } catch (_) {}
  }
}

