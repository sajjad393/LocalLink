import 'package:flutter/material.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This contact is not currently available.')),
        );
      }
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
              await Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => CallScreen(
                    controller: widget.calls,
                    initialSession: session,
                  ),
                ),
              );
            }
          },
        ),
      ),
    );
  }

  Future<void> _addContact() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => AddContactScreen(
          repository: widget.directory,
          crypto: widget.crypto,
          onStartChat: _chat,
        ),
      ),
    );
    await bloc.load();
  }

  @override
  void dispose() {
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
            tooltip: 'Nearby Devices',
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => NearbyDevicesScreen(connectivity: widget.connectivity),
              ),
            ),
            icon: const Icon(Icons.wifi_find),
          ),
          IconButton(
            tooltip: 'Add Contact',
            onPressed: _addContact,
            icon: const Icon(Icons.person_add_alt_1),
          ),
        ],
      ),
      body: StreamBuilder<List<DirectoryProfile>>(
        stream: bloc.stream,
        initialData: bloc.state,
        builder: (context, snapshot) {
          final contacts = snapshot.data ?? const <DirectoryProfile>[];
          return RefreshIndicator(
            onRefresh: bloc.load,
            child: contacts.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 180),
                      Center(child: Text('No contacts yet')),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: contacts.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final profile = contacts[index];
                      final title = profile.displayName.isEmpty
                          ? profile.username
                          : profile.displayName;
                      return ListTile(
                        leading: CircleAvatar(
                          child: Text(
                            title.isEmpty ? '?' : title[0].toUpperCase(),
                          ),
                        ),
                        title: Text(title),
                        subtitle: Text(
                          '@${profile.username}${profile.phoneNumber.isEmpty ? '' : ' • ${profile.phoneNumber}'}',
                        ),
                        onTap: () => _chat(profile),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) async {
                            if (value == 'remove') {
                              await bloc.remove(profile.userId);
                            } else if (value == 'block') {
                              await bloc.block(profile.userId);
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'remove',
                              child: Text('Remove contact'),
                            ),
                            PopupMenuItem(
                              value: 'block',
                              child: Text('Block user'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          );
        },
      ),
    );
  }
}
