import 'package:locallink/core/widgets/link_toast.dart';
import 'package:locallink/core/diagnostics/ui_hidden_263.dart';
import 'package:locallink/features/authentication/data/services/offline_publish_ticker_256.dart';
import 'package:locallink/features/directory/presentation/add_friend_256.dart';
import 'package:locallink/core/presence/block_hub.dart';
import 'package:locallink/features/directory/presentation/contact_sheets.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:locallink/core/bloc/bloc_utils.dart';
import 'package:locallink/core/presence/presence_hub.dart';

import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/features/directory/bloc/directory_bloc.dart';
import 'package:locallink/features/directory/domain/directory_models.dart';
import 'package:locallink/features/directory/domain/directory_repository_contract.dart';
import 'package:locallink/features/directory/presentation/my_qr_screen.dart';
import 'package:locallink/features/connectivity/bloc/connectivity_bloc.dart';
import 'package:locallink/features/connectivity/bloc/mesh_bloc.dart';
import 'package:locallink/features/directory/data/services/pairing_service.dart';
import 'package:locallink/features/directory/data/services/friend_hello_service.dart';
import 'package:locallink/features/directory/data/directory_search_merge.dart';
import 'package:locallink/features/directory/data/people_to_add_267.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/features/directory/presentation/nearby_people_section.dart';
import 'package:locallink/features/directory/presentation/add_contact_ui283.dart';
import 'package:locallink/core/widgets/link_kit_290.dart';
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
  bool _lastSearchByName = false; // Bundle 195a: the hint is for names only
  /// Token of the request whose results may land; stale responses die here.
  int _searchSeq = 0;

  /// Bundle 173: who is already a contact ("Added" instead of "Add").
  Set<String> _contactIds = const <String>{};

  // Bundle 267: the list under an empty search box (people to add).
  List<DirectoryProfile> _people267 = const <DirectoryProfile>[];
  String _peopleSource267 = 'none';
  bool _peopleLoading267 = false;
  bool _peopleMore267 = false;
  int _peopleNext267 = 0;
  bool _peopleSynced267 = false;
  bool? _serverUp267;
  StreamSubscription<ConnectivityState>? _serverSub267;

  /// Bundle 283: "Find people nearby" on the empty screen was tapped.
  bool _nearbyAsked283 = false;

  /// Bundle 283: my first letter for the middle of the search scene.
  String _meInitial283 = '';

  @override
  void initState() {
    super.initState();
    bloc = DirectoryBloc(widget.repository);
    query.addListener(_onQueryChanged);
    _loadContacts();
    // Bundle 267: people to add, shown while the search box is empty.
    if (widget.repository is PeopleSource267) {
      _peopleLoading267 = true;
      unawaited(_loadPeople267(force: true));
    }
    final c = widget.connectivity;
    if (c != null) {
      _serverUp267 = c.state.snapshot.serverConnected;
      _serverSub267 = c.stream.listen((state) {
        final up = state.snapshot.serverConnected;
        if (up == _serverUp267) return;
        _serverUp267 = up;
        if (mounted && widget.repository is PeopleSource267) {
          unawaited(_loadPeople267(force: true));
        }
      });
    }
    // Bundle 263 (F1): try the server / the phone-only upload on open.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _autoFind263();
    });
    unawaited(_loadMe283());
  }

  Future<void> _loadMe283() async {
    try {
      final me = await widget.pairing?.ownQrProfile242();
      if (me == null || !mounted) return;
      final name = me.displayName.trim().isNotEmpty ? me.displayName.trim() : me.username.trim();
      if (name.isNotEmpty) setState(() => _meInitial283 = name[0].toUpperCase());
    } catch (_) {}
  }

  Future<void> _loadContacts() async {
    try {
      final rows = await widget.repository.contacts();
      if (!mounted) return;
      setState(() => _contactIds = rows.map((p) => p.userId).toSet());
    } catch (_) {
      // Unknown: every result simply shows "Add".
    }
  }

  /// Bundle 173: Add straight from the search card (same name box as the
  /// profile page).
  Future<void> _addFromResults(DirectoryProfile profile) async {
    // Bundle 194: already my friend -> no add, no toast, open the chat.
    final hello = FriendHelloService.instance;
    if (hello != null &&
        profile.deviceId.isNotEmpty &&
        await hello.isFriend(profile.userId)) {
      if (!mounted) return;
      setState(() => _contactIds = {..._contactIds, profile.userId});
      await hello.openExistingChat(
          deviceId: profile.deviceId,
          displayName: profile.displayName,
          source: 'online');
      return;
    }
    if (!mounted) return;
    // Bundle 256 E1/E2: every tap and every failure is in the log.
    final source = DirectorySearchInfo.serverReached ? 'online' : 'friend_card';
    AppLogger.info('FRIEND_ADD_START', detail: 'source=$source');
    final customName =
        await showSaveContactDialog(context, profile.displayName);
    if (customName == null || !mounted) return;
    try {
      await widget.repository
          .addContact(profile.userId, customName: customName.trim());
      if (!mounted) return;
      setState(() => _contactIds = {..._contactIds, profile.userId});
      if (hello != null && profile.deviceId.isNotEmpty) {
        // Bundle 194: the chat opens and one "Hello 👋" follows.
        AppLogger.info('FRIEND_ADD_TAP', detail: 'source=online already=n');
        unawaited(hello.addedByMe(FriendAddedByMe(
          userId: profile.userId,
          deviceId: profile.deviceId,
          displayName: customName.trim().isNotEmpty
              ? customName.trim()
              : profile.displayName,
          source: 'online',
        )));
        return;
      }
      LinkToast.show(context, 'Contact added', kind: LinkToastKind.done);
    } catch (e) {
      logFriendAddFail256(source, e);
      if (mounted) _showError(friendAddFailText256(e));
    }
  }

  /// Bundle 267: first page ([force]) or the next server page. Server not
  /// reached -> the people nearby phones shared; then one sync with nearby
  /// phones and one reload.
  Future<void> _loadPeople267({bool force = false}) async {
    if (_peopleLoading267 && !force) return;
    if (!force && !_peopleMore267) return;
    final next = !force;
    setState(() => _peopleLoading267 = true);
    final page = await PeopleToAdd267.load(widget.repository,
        offset: next ? _peopleNext267 : 0);
    if (!mounted) return;
    setState(() {
      _peopleLoading267 = false;
      _peopleSource267 = page.source;
      _peopleMore267 = page.more;
      _peopleNext267 = page.nextOffset;
      _people267 = next ? [..._people267, ...page.people] : page.people;
    });
    if (!next && page.source == 'nearby' && !_peopleSynced267) {
      _peopleSynced267 = true;
      try {
        await widget.repository.sync();
      } catch (_) {}
      if (mounted) await _loadPeople267(force: true);
    }
  }

  @override
  void dispose() {
    unawaited(_serverSub267?.cancel());
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
        _lastSearchByName = !asPhone;
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
    LinkToast.show(context, message, kind: LinkToast.guess(message));
  }

  Future<void> _open(DirectoryProfile profile) async {
    await Navigator.push<void>(
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
    // Bundle 173: they may have been added on the profile page.
    if (mounted) await _loadContacts();
  }

  /// Bundle 242: opens My QR (the same screen as Profile).
  Future<void> _openMyQr242() async {
    final me = await widget.pairing?.ownQrProfile242();
    if (!mounted) return;
    if (me == null) {
      _showError('Your profile is not ready yet.');
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => MyQrScreen(profile: me, crypto: widget.crypto, repository: widget.repository),
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
          // Bundle 283 (Q-2): the scanner's "My QR code" shows my code.
          myProfile: widget.pairing?.ownQrProfile242,
          onFound: (profile) {
            Navigator.pop(context);
            _open(profile);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Bundle 283 (mock 283): same look on every phone, dark + light.
    final p = LinkKit.of(context);
    return Scaffold(
      backgroundColor: p.screen,
      appBar: addBar283(
        context,
        title: 'Add Contact',
        // Bundle 242 (mock 242): My QR at the top right.
        actions: [
          RoundTopButton283(
            key: const ValueKey('add_contact_my_qr_242'),
            tooltip: 'My QR code',
            icon: Icons.qr_code_2_rounded,
            onPressed: _openMyQr242,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SearchBox283(
                controller: query,
                busy: searching,
                onClear: () => query.clear(), // listener re-syncs state
              ),
            ),
            // Bundle 196 (11.3): blocked matches change with BlockHub.
            Expanded(
              child: ListenableBuilder(
                listenable: BlockHub.instance,
                builder: (context, _) => _buildResults(context),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: ScanButton283(onPressed: searching ? null : _scan),
            ),
          ],
        ),
      ),
    );
  }

  /// Bundle 170: search results first. Bundle 267: an empty box shows the
  /// people to add (server, or what nearby phones shared); Nearby appears
  /// only after a search found no one ("People nearby" + please wait).
  Widget _buildResults(BuildContext context) {
    final text = query.text.trim();
    final typing = text.length >= 2;
    // Bundle 196 (11.3): people I blocked who match, first (local only).
    final lower = text.toLowerCase().replaceFirst(RegExp('^@'), '');
    final blockedMatches = !typing
        ? const <BlockedPerson>[]
        : BlockHub.instance.people
            .where((p) =>
                p.label.toLowerCase().contains(lower) ||
                p.username.toLowerCase().contains(lower))
            .toList();
    final results = _results
        .where((p) => !BlockHub.instance.isBlockedUser(p.userId))
        .toList();
    final noMatch =
        typing && _noMatch && !searching && blockedMatches.isEmpty;
    // A Column (not a lazy list) so the Nearby part keeps its state while
    // results come and go above it.
    final scroll = SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (typing && (results.isNotEmpty || blockedMatches.isNotEmpty)) ...[
          const SectionTitle283('Results'),
          for (final person in blockedMatches)
            BlockedResultCard(
              key: ValueKey('search_blocked_${person.userId}'),
              person: person,
              onUnblock: () => runUnblockFlow(context, person, from: 'search'),
            ),
          // Bundle 173: same card as Nearby + status dot + Add button.
          for (var i = 0; i < results.length; i++)
            SlideIn283(
              key: ValueKey('search_in_${results[i].userId}'),
              delay: Duration(milliseconds: 120 * (i < 4 ? i : 4)),
              child: SearchResultCard(
                key: ValueKey('search_result_${results[i].userId}'),
                profile: results[i],
                initial: _initial(results[i]),
                isContact: _contactIds.contains(results[i].userId),
                onOpen: () => _open(results[i]),
                onAdd: () => _addFromResults(results[i]),
              ),
            ),
        ],
        if (noMatch) SlideIn283(child: NotFoundCard283(query: text)),
        // Bundle 195a: the server could not be asked -> say how to find more.
        if (_lastSearchByName &&
            DirectorySearchInfo.showOfflineHint(noMatch: noMatch))
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              DirectorySearchInfo.offlineHint,
              key: const ValueKey('search_offline_hint'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: LinkKit.of(context).muted),
            ),
          ),
        if (!typing && !(_nearbyAsked283 && _hasNearby)) ..._people267Section(),
        // Bundle 267: Nearby only after a search found no one; it starts
        // its search the moment it is shown. Bundle 283: or when the empty
        // screen's "Find people nearby" was tapped.
        if (_hasNearby && noMatch)
          _nearby283()
        else if (_hasNearby && _nearbyAsked283 && !typing)
          _nearby283(),
        if (noMatch) const SlideIn283(delay: Duration(milliseconds: 300), child: QrHint283()),
        const SizedBox(height: 12),
      ],
      ),
    );
    if (typing) return scroll;
    // Bundle 267: pull down = reload; near the end = next server page.
    return RefreshIndicator(
      onRefresh: () => _loadPeople267(force: true),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.extentAfter < 300 &&
              _peopleMore267 &&
              !_peopleLoading267) {
            unawaited(_loadPeople267());
          }
          return false;
        },
        child: scroll,
      ),
    );
  }

  Widget _nearby283() => NearbyPeopleSection(
        key: _nearbyKey,
        connectivity: widget.connectivity!,
        mesh: widget.mesh!,
        directory: widget.repository,
        crypto: widget.crypto,
        pairing: widget.pairing!,
        selfUserId: widget.selfUserId,
        title: 'People nearby',
        waitLine: PeopleToAdd267.waitLine,
        meInitial: _meInitial283,
      );

  /// Bundle 267: the people-to-add list (same cards as the search results).
  /// Bundle 283: nobody to show = the empty screen with two actions.
  List<Widget> _people267Section() {
    final shown = [
      for (final p in _people267)
        if (!_contactIds.contains(p.userId) &&
            !BlockHub.instance.isBlockedUser(p.userId))
          p,
    ];
    final server = _peopleSource267 == 'server';
    return [
      if (shown.isNotEmpty)
        SectionTitle283(
          server ? PeopleToAdd267.titleServer : PeopleToAdd267.titleNearby,
          key: const ValueKey('people267_title'),
        ),
      for (var i = 0; i < shown.length; i++)
        SlideIn283(
          key: ValueKey('people267_in_${shown[i].userId}'),
          delay: Duration(milliseconds: 120 * (i < 4 ? i : 4)),
          child: SearchResultCard(
            key: ValueKey('people267_${shown[i].userId}'),
            profile: shown[i],
            initial: _initial(shown[i]),
            isContact: false,
            onOpen: () => _open(shown[i]),
            onAdd: () => _addFromResults(shown[i]),
          ),
        ),
      if (_peopleLoading267)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2, color: LinkKit.of(context).focus),
            ),
          ),
        )
      else if (shown.isEmpty)
        EmptyAdd283(
          title: server ? PeopleToAdd267.emptyServerTitle : PeopleToAdd267.emptyNearbyTitle,
          text: server ? PeopleToAdd267.emptyServer : PeopleToAdd267.emptyNearby,
          textKey: const ValueKey('people267_empty'),
          icon: server ? Icons.check : Icons.person_search_rounded,
          onMyQr: _openMyQr242,
          onNearby: _hasNearby ? _openNearby283 : null,
        ),
    ];
  }

  void _openNearby283() {
    UiHidden263.note('add_nearby', 'from=empty');
    setState(() => _nearbyAsked283 = true);
  }

  // ------------------------------------------------------- Bundle 263 B5
  /// No "Server connected / No server - searching nearby phones" line any
  /// more: opening Add friend does what "Find server now" did, by itself.
  void _autoFind263() {
    final ticker = OfflinePublishTicker256.instance;
    if (ticker.active) {
      UiHidden263.note('add_status', 'phone_only=y');
      ticker.nudge('add_open');
      return;
    }
    UiHidden263.note('add_status',
        'server=${widget.connectivity?.state.snapshot.serverConnected == true ? 'y' : 'n'}');
    final c = widget.connectivity;
    if (c != null && !c.state.snapshot.serverConnected) {
      unawaited(c.refresh().catchError((Object _) {}));
    }
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

  Future<String?> _contactNameDialog(BuildContext context) =>
      showSaveContactDialog(context, profile.displayName);

  Future<void> _addContact(BuildContext context) async {
    // Bundle 194: already my friend -> no add, no toast, open the chat.
    final hello = FriendHelloService.instance;
    if (hello != null &&
        profile.deviceId.isNotEmpty &&
        await hello.isFriend(profile.userId)) {
      if (!context.mounted) return;
      await hello.openExistingChat(
          deviceId: profile.deviceId,
          displayName: profile.displayName,
          source: 'profile');
      return;
    }
    if (!context.mounted) return;
    final customName = await _contactNameDialog(context);
    if (customName == null || !context.mounted) return;
    try {
      await widget.repository
          .addContact(profile.userId, customName: customName.trim());
      if (hello != null && profile.deviceId.isNotEmpty) {
        // Bundle 194: the chat opens and one "Hello 👋" follows.
        AppLogger.info('FRIEND_ADD_TAP', detail: 'source=profile already=n');
        if (mounted) setState(() => _isContact = true);
        unawaited(hello.addedByMe(FriendAddedByMe(
          userId: profile.userId,
          deviceId: profile.deviceId,
          displayName: customName.trim().isNotEmpty
              ? customName.trim()
              : profile.displayName,
          source: 'profile',
        )));
        return;
      }
      if (context.mounted) {
        LinkToast.show(context, 'Contact added', kind: LinkToastKind.done);
        setState(() => _isContact = true);
        _loadPrivacy();
      }
    } catch (e) {
      logFriendAddFail256('profile', e); // Bundle 256 E2
      if (!context.mounted) return;
      LinkToast.show(context, friendAddFailText256(e), kind: LinkToastKind.error);
    }
  }

  String get _name =>
      profile.displayName.isEmpty ? profile.username : profile.displayName;

  /// Bundle 196 (7.3): asks first; the page then shows the blocked view.
  Future<void> _block(BuildContext context) async {
    final done = await runBlockFlow(context,
        userId: profile.userId,
        name: _name,
        username: profile.username,
        from: 'profile',
        block: widget.repository.blockUser);
    if (done && mounted) setState(() => _isContact = false);
  }

  BlockedPerson _blockedPerson() =>
      BlockHub.instance.personForUser(profile.userId) ??
      BlockedPerson(
        userId: profile.userId,
        deviceId: profile.deviceId,
        name: _name,
        username: profile.username,
      );

  /// Bundle 196 (11.2): the two buttons on a blocked profile (no sheet).
  Future<void> _unblock(BuildContext context, {required bool addBack}) async {
    final hub = BlockHub.instance;
    final person = _blockedPerson();
    final messenger = ScaffoldMessenger.of(context);
    AppLogger.info('CONTACT_UNBLOCK',
        detail: 'add_back=${addBack ? 'y' : 'n'} from=profile');
    try {
      if (addBack && hub.unblockAndAdd != null) {
        await hub.unblockAndAdd!(person);
      } else if (hub.unblock != null) {
        await hub.unblock!(person.userId);
      } else {
        await widget.repository.unblockUser(person.userId);
      }
      await hub.reload();
      if (mounted) setState(() => _isContact = addBack ? true : _isContact);
      LinkToast.maybeOn(messenger, addBack
              ? '${person.label} unblocked and added back'
              : '${person.label} unblocked', kind: LinkToastKind.done);
      _loadPrivacy();
    } catch (e) {
      LinkToast.maybeOn(messenger, cleanBlocError(e), kind: LinkToastKind.error);
    }
  }

  List<Widget> _blockedView(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final when = blockDateLabel(_blockedPerson().blockedAt);
    return [
      Center(child: MutedAvatar(name: _name, radius: 48)),
      const SizedBox(height: 16),
      Center(
        child: Text(_name,
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center),
      ),
      if (profile.username.isNotEmpty)
        Center(child: Text('@${profile.username}')),
      const SizedBox(height: 10),
      Center(
        child: Container(
          key: const ValueKey('profile_blocked_chip'),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: scheme.errorContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.block, size: 16, color: scheme.error),
              const SizedBox(width: 6),
              Text('Blocked',
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: scheme.error)),
            ],
          ),
        ),
      ),
      const SizedBox(height: 14),
      Text(
        when.isEmpty
            ? "You blocked $_name. They can't message or call you."
            : "You blocked $_name on $when. They can't message or call you.",
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
      ),
      const SizedBox(height: 20),
      FilledButton(
        key: const ValueKey('profile_unblock_add_back'),
        onPressed: () => _unblock(context, addBack: true),
        child: const Text('Unblock and add back'),
      ),
      const SizedBox(height: 10),
      OutlinedButton(
        key: const ValueKey('profile_unblock_only'),
        onPressed: () => _unblock(context, addBack: false),
        child: const Text('Unblock only'),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: BlockHub.instance,
        builder: (context, _) => _page(context),
      );

  Widget _page(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Profile')),
        body: BlockHub.instance.isBlockedUser(profile.userId) &&
                _relation != ProfileRelation.self
            ? ListView(
                padding: const EdgeInsets.all(20),
                children: _blockedView(context),
              )
            : ListView(
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
}

/// Bundle 111: choose the LOCAL display name at add time. Cancelling
/// aborts the add; clearing the field keeps the profile name as-is.
Future<String?> showSaveContactDialog(BuildContext context, String initialName) {
  final controller =
      TextEditingController(text: initialName);
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

/// Bundle 173: one search result - the same filled card as Nearby, the
/// usual status dot on the photo, and Add (or "Added" for a contact).
class SearchResultCard extends StatelessWidget {
  final DirectoryProfile profile;
  final String initial;
  final bool isContact;
  final VoidCallback onOpen;
  final VoidCallback onAdd;

  const SearchResultCard({
    super.key,
    required this.profile,
    required this.initial,
    required this.isContact,
    required this.onOpen,
    required this.onAdd,
  });

  static String statusWord(String channel) => switch (channel) {
        'nearby' => 'Nearby',
        'server' => 'Online',
        _ => 'Offline',
      };

  /// Bundle 283 (mock): teal dot = nearby, blue dot = online, none = offline.
  static Color? dotColor(String channel) => switch (channel) {
        'nearby' => const Color(0xFF14A3A0),
        'server' => const Color(0xFF3B82C4),
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final name =
        profile.displayName.isEmpty ? profile.username : profile.displayName;
    final hasDevice = profile.deviceId.trim().isNotEmpty;
    // Bundle 283 (mock): one card look; "✓ Contact" pill or gradient Add.
    return ListenableBuilder(
      listenable: PresenceHub.instance,
      builder: (context, _) {
        final channel =
            hasDevice ? PresenceHub.instance.channelOf(profile.deviceId) : '';
        final status = hasDevice ? statusWord(channel) : 'Offline';
        return PersonCard283(
          onTap: onOpen,
          avatar: LetterAvatar283(
              name: name, initial: initial, dot: hasDevice ? dotColor(channel) : null),
          title: name,
          subtitle: Text(isContact
              ? '@${profile.username}'
              : '@${profile.username} · $status'),
          trailing: isContact
              ? const ContactPill283('Contact', key: Key('search_result_added'))
              : GradientChip283(
                  key: const Key('search_result_add'),
                  text: 'Add',
                  onPressed: onAdd,
                ),
        );
      },
    );
  }
}

/// Bundle 196 (11.3): a person I blocked in the search results (local only):
/// muted avatar, "@user" + Blocked pill, outlined "Unblock".
/// Bundle 283: same card shape as the other results.
class BlockedResultCard extends StatelessWidget {
  final BlockedPerson person;
  final VoidCallback onUnblock;

  const BlockedResultCard(
      {super.key, required this.person, required this.onUnblock});

  @override
  Widget build(BuildContext context) {
    final p = LinkKit.of(context);
    return PersonCard283(
      onTap: onUnblock,
      avatar: MutedAvatar(name: person.label, radius: 22),
      title: person.label,
      titleColor: p.muted,
      subtitle: Align(
        alignment: Alignment.centerLeft,
        child: BlockedUserLine(username: person.username),
      ),
      trailing: OutlinedButton(
        key: const Key('search_result_unblock'),
        onPressed: onUnblock,
        style: OutlinedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          foregroundColor: p.text,
          side: BorderSide(color: AddUi283.chevron(p)),
          shape: const StadiumBorder(),
        ),
        child: const Text('Unblock'),
      ),
    );
  }
}
