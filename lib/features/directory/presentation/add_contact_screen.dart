import 'dart:async';

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

  // Bundle 98: live search — results refresh as the user types (debounced)
  // and render inline on this page instead of the one-shot bottom sheet.
  Timer? _debounce;
  List<DirectoryProfile> _results = const [];
  bool _noMatch = false;
  /// Token of the request whose results may land; stale responses die here.
  int _searchSeq = 0;

  @override
  void initState() {
    super.initState();
    bloc = DirectoryBloc(widget.repository);
    query.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    query.dispose();
    bloc.close();
    super.dispose();
  }

  void _onQueryChanged() {
    _debounce?.cancel();
    final text = query.text.trim();
    if (text.length < 2) {
      setState(() {
        searching = false;
        _results = const [];
        _noMatch = false;
      });
      return;
    }
    setState(() => searching = true);
    _debounce = Timer(const Duration(milliseconds: 350), () => _runSearch(text));
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

  Future<void> _runSearch(String text) async {
    final seq = ++_searchSeq;
    final asPhone = _looksLikePhone(text);
    bloc.add(asPhone ? SearchDirectoryByPhone(text) : SearchDirectoryByName(text));
    final state = await _waitForResult();
    if (!mounted) return;
    // A newer keystroke re-issued the query while this one was in flight —
    // drop the stale response silently instead of flashing old results.
    if (seq != _searchSeq || query.text.trim() != text) return;
    setState(() => searching = false);
    if (state is DirectoryResults) {
      setState(() {
        _results = state.profiles;
        _noMatch = state.profiles.isEmpty;
      });
    } else if (state is DirectoryError) {
      _showError(state.message);
    }
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
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: query,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search',
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
                                : () => query.clear(), // listener re-syncs state
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
                const SizedBox(height: 16),
                Expanded(child: _buildResults(context)),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: searching ? null : _scan,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan QR code'),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _buildResults(BuildContext context) {
    if (query.text.trim().length < 2) {
      return Center(
        child: Text(
          'Type at least 2 characters to search.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    if (_noMatch && !searching) {
      return Center(
        child: Text(
          'No matching users found',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    if (_results.isEmpty) return const SizedBox.shrink();
    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final profile = _results[index];
        return ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Theme.of(context).dividerColor),
          ),
          tileColor: Theme.of(context).colorScheme.surface,
          leading: CircleAvatar(child: Text(_initial(profile))),
          title: Text(profile.displayName.isEmpty
              ? profile.username
              : profile.displayName),
          subtitle: Text('@${profile.username}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _open(profile),
        );
      },
    );
  }
}

class DirectoryProfileView extends StatefulWidget {
  final DirectoryProfile profile;
  final DirectoryRepositoryContract repository;
  final Future<void> Function(DirectoryProfile)? onStartChat;

  const DirectoryProfileView({
    super.key,
    required this.profile,
    required this.repository,
    this.onStartChat,
  });

  @override
  State<DirectoryProfileView> createState() => _DirectoryProfileViewState();
}

class _DirectoryProfileViewState extends State<DirectoryProfileView> {
  /// null until the contact-status probe resolves; hidden for non-contacts.
  bool? _isPrivate;

  DirectoryProfile get profile => widget.profile;

  @override
  void initState() {
    super.initState();
    _loadPrivacy();
  }

  Future<void> _loadPrivacy() async {
    try {
      final rows = await widget.repository.contacts();
      final isContact = rows.any((p) => p.userId == profile.userId);
      if (!isContact) return;
      if (!mounted) return;
      setState(() => _isPrivate = false);
      final value = await widget.repository.contactPrivate(profile.userId);
      if (mounted) setState(() => _isPrivate = value);
    } catch (_) {}
  }

  String _initial() {
    final value = profile.displayName.isEmpty
        ? profile.username
        : profile.displayName;
    return value.isEmpty ? '?' : value[0].toUpperCase();
  }

  /// Bundle 111: choose the LOCAL display name at add time. Cancelling
  /// aborts the add; clearing the field keeps the profile name as-is.
  Future<String?> _contactNameDialog(BuildContext context) {
    final controller =
        TextEditingController(text: profile.displayName);
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Save contact as'),
        content: TextField(
          controller: controller,
          autocorrect: false,
          maxLength: 40,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Name on this phone',
            hintText: 'Only you will see this name',
          ),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Add contact'),
          ),
        ],
      ),
    ).then((value) {
      controller.dispose();
      return value;
    });
  }

  Future<void> _addContact(BuildContext context) async {
    final customName = await _contactNameDialog(context);
    if (customName == null || !context.mounted) return;
    try {
      await widget.repository
          .addContact(profile.userId, customName: customName.trim());
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contact added')),
        );
        // Reveal the privacy toggle for the freshly added contact.
        setState(() => _isPrivate ??= false);
        _loadPrivacy();
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
      await widget.repository.blockUser(profile.userId);
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
            if (_isPrivate != null)
              SwitchListTile(
                title: const Text('Searchable by others'),
                subtitle: Text(_isPrivate!
                    ? 'Private — this contact is not re-shared from your phone'
                    : 'Public — shared onward so anyone searching can find them'),
                value: !_isPrivate!,
                onChanged: (value) async {
                  final makePrivate = !value;
                  setState(() => _isPrivate = makePrivate);
                  try {
                    await widget.repository
                        .setContactPrivate(profile.userId, makePrivate);
                  } catch (e) {
                    if (!mounted || !context.mounted) return;
                    setState(() => _isPrivate = !makePrivate);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('Could not update privacy: $e')));
                  }
                },
              ),
            if (widget.onStartChat != null)
              OutlinedButton.icon(
                onPressed: () => widget.onStartChat!(profile),
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
