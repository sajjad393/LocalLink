import 'package:flutter/material.dart';

import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/core/widgets/account_avatar.dart';
import 'package:locallink/core/widgets/local_link_state_view.dart';
import 'package:locallink/core/widgets/messenger_section_header.dart';
import 'package:locallink/features/calls/bloc/call_bloc.dart';
import 'package:locallink/features/calls/presentation/screens/call_screen.dart';
import 'package:locallink/features/connectivity/bloc/connectivity_bloc.dart';
import 'package:locallink/features/directory/bloc/contacts_bloc.dart';
import 'package:locallink/features/directory/domain/directory_models.dart';
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
  final ConnectivityBloc connectivity;
  final MessagingRepositoryContract messaging;
  final FileTransferRepositoryContract files;
  final CallBloc calls;
  final IdentityCryptoService crypto;
  final LocalLinkNotificationService notifications;

  const ContactsScreen({
    super.key,
    required this.directory,
    required this.connectivity,
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
            if (session != null && context.mounted) {
              await Navigator.push<void>(context, MaterialPageRoute(builder: (_) => CallScreen(controller: widget.calls, initialSession: session)));
            }
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
        title: const Text('People'),
        actions: [
          IconButton(
            tooltip: 'Nearby',
            onPressed: () => Navigator.push<void>(context, MaterialPageRoute(builder: (_) => NearbyDevicesScreen(connectivity: widget.connectivity))),
            icon: const Icon(Icons.wifi_find),
          ),
          IconButton(tooltip: 'Add contact', onPressed: _addContact, icon: const Icon(Icons.person_add_alt_1)),
        ],
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
                      title: query.isEmpty ? 'No contacts yet' : 'No people found',
                      message: query.isEmpty ? 'Add a contact or discover nearby LocalLink phones.' : 'Try another name or username.',
                      actionLabel: query.isEmpty ? 'Add contact' : null,
                      onAction: query.isEmpty ? _addContact : null,
                    ),
                  )
                else
                  ...contacts.map((profile) {
                    final title = profile.displayName.isEmpty ? profile.username : profile.displayName;
                    return ListTile(
                      minVerticalPadding: LocalLinkSpacing.sm,
                      leading: AccountAvatar(name: title, radius: 24),
                      title: Text(title, style: Theme.of(context).textTheme.titleSmall),
                      subtitle: Text('@${profile.username}', maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: PopupMenuButton<String>(
                        tooltip: 'More',
                        onSelected: (value) async {
                          if (value == 'remove') await bloc.remove(profile.userId);
                          if (value == 'block') await bloc.block(profile.userId);
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'remove', child: Text('Remove contact')),
                          PopupMenuItem(value: 'block', child: Text('Block person')),
                        ],
                      ),
                      onTap: () => _chat(profile),
                    );
                  }),
              ],
            ),
          );
        },
      ),
    );
  }
}
