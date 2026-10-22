import 'package:flutter/material.dart';
import 'package:locallink/core/bloc/bloc_utils.dart';

import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/features/directory/bloc/directory_bloc.dart';
import 'package:locallink/features/directory/domain/directory_models.dart';
import 'package:locallink/features/directory/domain/directory_repository_contract.dart';
import 'package:locallink/features/directory/presentation/my_qr_screen.dart';

class AddContactScreen extends StatefulWidget {
  final DirectoryRepositoryContract repository;
  final Future<void> Function(DirectoryProfile)? onStartChat;
  final IdentityCryptoService crypto;

  const AddContactScreen({
    super.key,
    required this.repository,
    required this.crypto,
    this.onStartChat,
  });

  @override
  State<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends State<AddContactScreen> {
  final query = TextEditingController();
  late final DirectoryBloc bloc;
  bool searching = false;

  @override
  void initState() {
    super.initState();
    bloc = DirectoryBloc(widget.repository);
    query.addListener(() => setState(() {})); // keeps the clear icon in sync
  }

  @override
  void dispose() {
    query.dispose();
    bloc.close();
    super.dispose();
  }

  Future<DirectoryState> _waitForResult() => bloc.stream.firstWhere(
        (state) => state is DirectoryResults || state is DirectoryError,
      );

  /// Phone if it consists (mostly) of digits/+/-/()/spaces with >= 5 digits;
  /// anything else is treated as a name/username query.
  static bool _looksLikePhone(String raw) {
    if (!RegExp(r'^[+0-9()\- ]+$').hasMatch(raw)) return false;
    return raw.replaceAll(RegExp(r'[^0-9]'), '').length >= 5;
  }

  Future<void> _search() async {
    final text = query.text.trim();
    if (text.isEmpty || searching) return;
    setState(() => searching = true);
    final asPhone = _looksLikePhone(text);
    bloc.add(asPhone ? SearchDirectoryByPhone(text) : SearchDirectoryByName(text));
    final state = await _waitForResult();
    if (!mounted) return;
    setState(() => searching = false);
    if (state is DirectoryResults) {
      if (state.profiles.isEmpty) {
        _showError('No matching users found');
      } else if (state.profiles.length == 1) {
        _open(state.profiles.first);
      } else {
        _showResults(state.profiles);
      }
    } else if (state is DirectoryError) {
      _showError(state.message);
    }
  }

  void _showResults(List<DirectoryProfile> rows) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Search results')),
            ...rows.map(
              (profile) => ListTile(
                leading: CircleAvatar(
                  child: Text(
                    _initial(profile),
                  ),
                ),
                title: Text(
                  profile.displayName.isEmpty
                      ? profile.username
                      : profile.displayName,
                ),
                subtitle: Text('@${profile.username}'),
                onTap: () {
                  Navigator.pop(context);
                  _open(profile);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _initial(DirectoryProfile profile) {
    final value = profile.displayName.isEmpty
        ? profile.username
        : profile.displayName;
    return value.isEmpty ? '?' : value[0].toUpperCase();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _open(DirectoryProfile profile) {
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => DirectoryProfileView(
          profile: profile,
          repository: widget.repository,
          onStartChat: widget.onStartChat,
        ),
      ),
    );
  }

  Future<void> _scan() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ContactQrScannerScreen(
          crypto: widget.crypto,
          repository: widget.repository,
          onFound: (profile) {
            Navigator.pop(context);
            _open(profile);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Add Contact')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Find someone on LocalLink',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              'Search by name, @username, or phone number — or scan a QR code.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 22),
            TextField(
              controller: query,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: 'Name, username, or phone number',
                filled: true,
                prefixIcon: searching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : const Icon(Icons.search),
                suffixIcon: query.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: searching
                            ? null
                            : () => setState(query.clear),
                        icon: const Icon(Icons.close),
                        tooltip: 'Clear',
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
              ),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: searching ? null : _scan,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan QR code'),
            ),

          ],
        ),
      );
}

class DirectoryProfileView extends StatelessWidget {
  final DirectoryProfile profile;
  final DirectoryRepositoryContract repository;
  final Future<void> Function(DirectoryProfile)? onStartChat;

  const DirectoryProfileView({
    super.key,
    required this.profile,
    required this.repository,
    this.onStartChat,
  });

  String _initial() {
    final value = profile.displayName.isEmpty
        ? profile.username
        : profile.displayName;
    return value.isEmpty ? '?' : value[0].toUpperCase();
  }

  Future<void> _addContact(BuildContext context) async {
    try {
      await repository.addContact(profile.userId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contact added')),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            cleanBlocError(e),
          ),
        ),
      );
    }
  }

  Future<void> _block(BuildContext context) async {
    try {
      await repository.blockUser(profile.userId);
      if (context.mounted) Navigator.pop(context);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(cleanBlocError(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Profile')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: CircleAvatar(
                radius: 48,
                child: Text(_initial(), style: const TextStyle(fontSize: 30)),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                profile.displayName.isEmpty
                    ? profile.username
                    : profile.displayName,
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
            ),
            if (profile.username.isNotEmpty)
              Center(child: Text('@${profile.username}')),
            if (profile.phoneNumber.isNotEmpty) ...[
              const SizedBox(height: 6),
              Center(child: Text(profile.phoneNumber)),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _addContact(context),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Add Contact'),
            ),
            if (onStartChat != null)
              OutlinedButton.icon(
                onPressed: () => onStartChat!(profile),
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('Message'),
              ),
            TextButton(
              onPressed: () => _block(context),
              child: const Text('Block user'),
            ),
          ],
        ),
      );

}
