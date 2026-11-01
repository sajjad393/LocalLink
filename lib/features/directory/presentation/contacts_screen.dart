import 'package:flutter/material.dart';

import 'package:locallink/core/widgets/messenger_conversation_tile.dart' show PresenceAvatar;
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/core/widgets/account_avatar.dart';
import 'package:locallink/core/widgets/local_link_state_view.dart';
import 'package:locallink/core/presence/presence_hub.dart';
import 'package:locallink/core/widgets/messenger_list_group.dart';
import 'package:locallink/core/widgets/tab_top_bar.dart';
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
  }

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
      floatingActionButton: FloatingActionButton(
        heroTag: 'add_contact_fab',
        tooltip: 'Add contact',
        onPressed: _addContact,
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Ink(
          decoration: const BoxDecoration(
            gradient: LocalLinkBrand.linearGradient,
            shape: BoxShape.circle,
          ),
          child: const SizedBox(
            width: 56,
            height: 56,
            child: Icon(Icons.add, color: Colors.white, size: 28),
          ),
        ),
      ),
      body: StreamBuilder<List<DirectoryProfile>>(
        stream: bloc.stream,
        initialData: bloc.state,
        builder: (context, snapshot) => ListenableBuilder(
          // Bundle 183 (N8): the filtered list follows status changes live.
          listenable: PresenceHub.instance,
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
              ],
            ),
          );
          },
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
              ? AccountAvatar(name: title, radius: 24)
              : PresenceAvatar(
                  avatar: AccountAvatar(name: title, radius: 24),
                  device: _device(profile),
                ),
          title: Text(title, style: Theme.of(context).textTheme.titleSmall),
          subtitle: Text('@${profile.username}',
              maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (value) async {
              if (value == 'remove') await bloc.remove(profile.userId);
              if (value == 'block') await bloc.block(profile.userId);
              if (value == 'privacy') await _editPrivacy(profile);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: 'privacy', child: Text('Contact privacy…')),
              PopupMenuItem(value: 'remove', child: Text('Remove contact')),
              PopupMenuItem(value: 'block', child: Text('Block person')),
            ],
          ),
          onTap: () => _chat(profile),
        ),
      );
    }
    return MessengerListGroup(children: tiles);
  }

  Future<void> _editPrivacy(DirectoryProfile profile) async {
    var isPrivate = true;
    try {
      isPrivate = await widget.directory.contactPrivate(profile.userId);
    } catch (_) {}
    if (!mounted) return;
    final name = profile.displayName.isEmpty
        ? profile.username
        : profile.displayName;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => AlertDialog(
          title: Text(name),
          content: SwitchListTile(
            title: const Text('Searchable by others'),
            subtitle: const Text(
              'Public contacts are shared onward so anyone searching can '
              'find them through you (server, Wi‑Fi Direct, mesh). '
              'Turning this off marks the contact private — only you know it.',
            ),
            value: !isPrivate,
            onChanged: (value) => setSheetState(() => isPrivate = !value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                // Bundle 162: the dialog is closed below, so its context is
                // gone — use this screen's messenger.
                final messenger = ScaffoldMessenger.of(this.context);
                Navigator.pop(context);
                try {
                  await widget.directory
                      .setContactPrivate(profile.userId, isPrivate);
                  if (!mounted) return;
                  messenger.showSnackBar(SnackBar(
                    content: Text(isPrivate
                        ? name + ' marked private'
                        : name + ' is public again'),
                  ));
                } catch (e) {
                  if (!mounted) return;
                  messenger.showSnackBar(
                      SnackBar(content: Text('Could not update privacy: ' + e.toString())));
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

