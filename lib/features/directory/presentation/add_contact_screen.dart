import 'dart:async';

import 'package:flutter/material.dart';
import 'package:locallink/core/bloc/bloc_utils.dart';

import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/features/directory/bloc/directory_bloc.dart';
import 'package:locallink/features/directory/domain/directory_models.dart';
import 'package:locallink/features/directory/domain/directory_repository_contract.dart';
import 'package:locallink/features/directory/presentation/my_qr_screen.dart';
import 'package:locallink/features/connectivity/bloc/connectivity_bloc.dart';
import 'package:locallink/features/connectivity/bloc/mesh_bloc.dart';
import 'package:locallink/features/directory/data/services/pairing_service.dart';
import 'package:locallink/features/directory/presentation/nearby_devices_screen.dart';
import 'package:locallink/features/directory/presentation/profile_view_rules.dart';

class AddContactScreen extends StatefulWidget {
  final DirectoryRepositoryContract repository;
  final Future<void> Function(DirectoryProfile)? onStartChat;
  final IdentityCryptoService crypto;

  /// Bundle 170: Nearby lives here now (the separate Nearby screen is
  /// gone). When these are null the Nearby part is simply not shown.
  final ConnectivityBloc? connectivity;
  final MeshBloc? mesh;
  final PairingService? pairing;

  /// Bundle 170: this account's user id ("This is you", own phones hidden).
  final String selfUserId;

  const AddContactScreen({
    super.key,
    required this.repository,
    required this.crypto,
    this.onStartChat,
    this.connectivity,
    this.mesh,
    this.pairing,
    this.selfUserId = '',
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
          selfUserId: widget.selfUserId,
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
                    hintText: 'Search name or @username',
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

  /// Bundle 170: search results first, then the Nearby people (always under
  /// the search box, narrowed while typing). No match → "No one called …
  /// found" and everyone nearby under "People nearby".
  Widget _buildResults(BuildContext context) {
    final text = query.text.trim();
    final typing = text.length >= 2;
    final noMatch = typing && _noMatch && !searching;
    final theme = Theme.of(context);
    // A Column (not a lazy list) so the Nearby part keeps its state while
    // results come and go above it.
    return SingleChildScrollView(
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (typing && _results.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Results',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          for (final profile in _results)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: theme.dividerColor),
                ),
                tileColor: theme.colorScheme.surface,
                leading: CircleAvatar(child: Text(_initial(profile))),
                title: Text(profile.displayName.isEmpty
                    ? profile.username
                    : profile.displayName),
                subtitle: Text('@${profile.username}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _open(profile),
              ),
            ),
          const SizedBox(height: 8),
        ],
        if (noMatch)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No one called "$text" found.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        if (_hasNearby)
          NearbyPeopleSection(
            key: _nearbyKey,
            connectivity: widget.connectivity!,
            mesh: widget.mesh!,
            directory: widget.repository,
            crypto: widget.crypto,
            pairing: widget.pairing!,
            selfUserId: widget.selfUserId,
            title: noMatch ? 'People nearby' : 'Nearby',
            filter: typing && !noMatch ? text : '',
          )
        else if (!typing)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Text(
              'Type at least 2 characters to search.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (noMatch)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'Or ask them to show their QR code',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
      ),
    );
  }

  /// Keeps one Nearby section (one search) for the life of this screen.
  final GlobalKey _nearbyKey = GlobalKey();

  bool get _hasNearby =>
      widget.connectivity != null &&
      widget.mesh != null &&
      widget.pairing != null;
}

class DirectoryProfileView extends StatefulWidget {
  final DirectoryProfile profile;
  final DirectoryRepositoryContract repository;
  final Future<void> Function(DirectoryProfile)? onStartChat;

  /// Bundle 170: this account's user id — your own profile shows
  /// "This is you" and no Add / Message / Block.
  final String selfUserId;

  const DirectoryProfileView({
    super.key,
    required this.profile,
    required this.repository,
    this.onStartChat,
    this.selfUserId = '',
  });

  @override
  State<DirectoryProfileView> createState() => _DirectoryProfileViewState();
}

class _DirectoryProfileViewState extends State<DirectoryProfileView> {
  /// null until the contact-status probe resolves; hidden for non-contacts.
  bool? _isPrivate;

  /// Bundle 170: null until the contacts list has been checked.
  bool? _isContact;

  DirectoryProfile get profile => widget.profile;

  ProfileRelation get _relation => profileRelation(
        profileUserId: profile.userId,
        selfUserId: widget.selfUserId,
        isContact: _isContact ?? false,
      );

  @override
  void initState() {
    super.initState();
    _loadPrivacy();
  }

  Future<void> _loadPrivacy() async {
    try {
      final rows = await widget.repository.contacts();
      final isContact = rows.any((p) => p.userId == profile.userId);
      if (!mounted) return;
      setState(() => _isContact = isContact);
      if (!isContact) return;
      setState(() => _isPrivate = false);
      final value = await widget.repository.contactPrivate(profile.userId);
      if (mounted) setState(() => _isPrivate = value);
    } catch (_) {
      if (mounted) setState(() => _isContact ??= false);
    }
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
        setState(() {
          _isContact = true;
          _isPrivate ??= false;
        });
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
            // Bundle 170: who this is.
            if (_isContact != null || _relation == ProfileRelation.self) ...[
              const SizedBox(height: 10),
              Center(child: _relationChip(context)),
            ],
            // Bundle 170: strangers see a masked number.
            if (profile.phoneNumber.isNotEmpty) ...[
              const SizedBox(height: 6),
              Center(
                child: Text(_relation == ProfileRelation.stranger
                    ? maskPhone(profile.phoneNumber)
                    : profile.phoneNumber),
              ),
            ],
            const SizedBox(height: 24),
            ..._actions(context),
          ],
        ),
      );

  Widget? _chipOrNull(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    switch (_relation) {
      case ProfileRelation.self:
        return Chip(
          avatar: Icon(Icons.person, size: 18, color: scheme.onPrimaryContainer),
          label: const Text('This is you'),
          backgroundColor: scheme.primaryContainer,
          side: BorderSide.none,
        );
      case ProfileRelation.contact:
        return Chip(
          avatar: Icon(Icons.check_circle, size: 18, color: scheme.primary),
          label: const Text('In your contacts'),
          side: BorderSide.none,
        );
      case ProfileRelation.stranger:
        return null;
    }
  }

  Widget _relationChip(BuildContext context) =>
      _chipOrNull(context) ?? const SizedBox.shrink();

  /// Bundle 170: buttons by who this is.
  ///  * you        → none
  ///  * contact    → Message (filled), privacy switch, Block (red)
  ///  * stranger   → Add Contact (filled), Message (outlined), Block (red)
  List<Widget> _actions(BuildContext context) {
    if (_relation == ProfileRelation.self) return const <Widget>[];
    // Wait for the contacts check so the buttons do not jump.
    if (_isContact == null) return const <Widget>[SizedBox(height: 48)];
    final scheme = Theme.of(context).colorScheme;
    final contact = _relation == ProfileRelation.contact;
    final block = TextButton(
      style: TextButton.styleFrom(foregroundColor: scheme.error),
      onPressed: () => _block(context),
      child: const Text('Block user'),
    );
    if (contact) {
      return [
        if (widget.onStartChat != null)
          FilledButton.icon(
            onPressed: () => widget.onStartChat!(profile),
            icon: const Icon(Icons.chat_bubble_outline),
            label: const Text('Message'),
          ),
        if (_isPrivate != null) ...[
          const SizedBox(height: 8),
          _privacySwitch(context),
        ],
        const SizedBox(height: 8),
        block,
      ];
    }
    return [
      FilledButton.icon(
        onPressed: () => _addContact(context),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add Contact'),
      ),
      if (widget.onStartChat != null) ...[
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => widget.onStartChat!(profile),
          icon: const Icon(Icons.chat_bubble_outline),
          label: const Text('Message'),
        ),
      ],
      const SizedBox(height: 8),
      block,
    ];
  }

  Widget _privacySwitch(BuildContext context) => SwitchListTile(
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
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Could not update privacy: $e')));
          }
        },
      );
}
