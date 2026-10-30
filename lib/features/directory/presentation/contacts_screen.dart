import 'package:flutter/material.dart';

import 'package:locallink/core/widgets/messenger_conversation_tile.dart' show PresenceAvatar;
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/core/widgets/account_avatar.dart';
import 'package:locallink/core/widgets/local_link_state_view.dart';
import 'package:locallink/core/widgets/messenger_section_header.dart';
import 'package:locallink/features/calls/bloc/call_bloc.dart';
import 'package:locallink/features/calls/presentation/screens/call_screen.dart';
import 'package:locallink/features/connectivity/bloc/connectivity_bloc.dart';
import 'package:locallink/features/connectivity/bloc/mesh_bloc.dart';
import 'package:locallink/features/directory/bloc/contacts_bloc.dart';
import 'package:locallink/features/directory/domain/directory_models.dart';
import 'package:locallink/features/directory/data/services/pairing_service.dart';
import 'package:locallink/features/directory/domain/directory_repository_contract.dart';
import 'package:locallink/features/directory/presentation/add_contact_screen.dart';
import 'package:locallink/features/directory/presentation/nearby_devices_screen.dart';
import 'package:locallink/features/files/domain/file_transfer_repository_contract.dart';
import 'package:locallink/features/messaging/bloc/chat_bloc.dart';
import 'package:locallink/features/messaging/domain/messaging_repository_contract.dart';
import 'package:locallink/features/messaging/presentation/screens/chat_screen.dart';
import 'package:locallink/core/notifications/local_link_notification_service.dart';

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
  });

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  late final ContactsBloc bloc;
  final _searchController = TextEditingController();
  String _query = '';

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
      MaterialPageRoute(builder: (_) => AddContactScreen(repository: widget.directory, crypto: widget.crypto, onStartChat: _chat)),
    );
    await bloc.load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    bloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contacts'),
        actions: [
          IconButton(
            tooltip: 'Nearby',
            onPressed: () => Navigator.push<void>(context, MaterialPageRoute(builder: (_) => NearbyDevicesScreen(
              connectivity: widget.connectivity,
              mesh: widget.mesh,
              directory: widget.directory,
              crypto: widget.crypto,
              pairing: widget.pairing,
            ))),
            icon: const Icon(Icons.wifi_find),
          ),
        ],
      ),
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
        builder: (context, snapshot) {
          final all = snapshot.data ?? const <DirectoryProfile>[];
          final query = _query.trim().toLowerCase();
          final contacts = query.isEmpty
              ? all
              : all.where((profile) {
                  final title = profile.displayName.isEmpty ? profile.username : profile.displayName;
                  return title.toLowerCase().contains(query) || profile.username.toLowerCase().contains(query);
                }).toList();

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
                    decoration: const InputDecoration(
                      hintText: 'Search people',
                      prefixIcon: Icon(Icons.search),
                      suffixIcon: Icon(Icons.tune_outlined),
                    ),
                  ),
                ),
                const MessengerSectionHeader(title: 'Your contacts'),
                if (contacts.isEmpty)
                  SizedBox(
                    height: 420,
                    child: LocalLinkEmptyView(
                      icon: Icons.people_outline,
                      lottieAsset: 'assets/animations/empty_inbox.json',
                      title: query.isEmpty ? 'No contacts yet' : 'No people found',
                      message: query.isEmpty ? 'Add a contact or discover nearby LocalLink phones.' : 'Try another name or username.',
                      actionLabel: query.isEmpty ? 'Add contact' : null,
                      onAction: query.isEmpty ? _addContact : null,
                    ),
                  )
                else
                  _contactGroup(context, contacts),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Contact rows grouped in the shared rounded-container language
  /// (subtle surface, 20 radius, hairline separators).
  Widget _contactGroup(BuildContext context, List<DirectoryProfile> contacts) {
    final colors = Theme.of(context).colorScheme;
    final tiles = <Widget>[];
    for (var i = 0; i < contacts.length; i++) {
      final profile = contacts[i];
      final title =
          profile.displayName.isEmpty ? profile.username : profile.displayName;
      if (i > 0) {
        tiles.add(
          Divider(height: 1, indent: 72, color: colors.outlineVariant.withValues(alpha: 0.4)),
        );
      }
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
    // Material provides the ListTile ink/background layer; the Container only
    // draws border + radius + horizontal margin.
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: LocalLinkSpacing.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.35)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: colors.surfaceContainer.withValues(alpha: 0.65),
        child: Column(children: tiles),
      ),
    );
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

