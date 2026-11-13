import 'dart:async';

import 'package:locallink/core/widgets/link_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:locallink/core/services/server_reach.dart';
import 'package:locallink/features/connectivity/data/services/wifi_radio_control_service.dart';
import 'package:locallink/features/directory/presentation/nearby_status_256.dart';
import 'package:locallink/core/presence/presence_hub.dart';
import 'package:locallink/core/bloc/bloc_utils.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/core/widgets/link_kit_290.dart';
import 'package:locallink/core/widgets/error_toast.dart';
import 'package:locallink/features/connectivity/bloc/connectivity_bloc.dart';
import 'package:locallink/features/connectivity/bloc/mesh_bloc.dart';
import 'package:locallink/features/connectivity/data/models/nearby_tag.dart';
import 'package:locallink/features/connectivity/data/models/wifi_direct_models.dart';
import 'package:locallink/features/connectivity/data/services/friend_link_memo.dart';
import 'package:locallink/features/connectivity/data/services/nearby_ble.dart';
import 'package:locallink/features/directory/domain/directory_repository_contract.dart';
import 'package:locallink/features/directory/data/services/pairing_service.dart';
import 'package:locallink/features/directory/data/friend_requests.dart';
import 'package:locallink/features/directory/data/services/friend_hello_service.dart';
import 'package:locallink/features/directory/presentation/nearby_list_plan.dart';
import 'package:locallink/features/directory/presentation/add_contact_ui283.dart';
import 'package:locallink/features/directory/presentation/profile_view_rules.dart';

/// Bundle 170: the Nearby list now lives INSIDE Add Contact (the separate
/// Nearby screen and its button on Contacts are gone). This section shows
/// the phones you can still add, under the search box:
///
/// * [filter] narrows the list while the user types (real names only);
///   when nothing matches the section hides itself.
/// * Nobody found yet → the mesh search animation.
/// * Someone found → a link draws to them, their circle pops in, then the
///   card slides up into the list and the mesh shrinks to 3 dots by the
///   title.
/// * Nearby permission off → a small "Allow" card; no popup by itself.
/// * Pair works as before and the list stays, so several people can be
///   added in a row. Your own other phones are never listed.
class NearbyPeopleSection extends StatefulWidget {
  final ConnectivityBloc connectivity;

  /// Mesh presence feed (LAN beacon discovery + Wi-Fi Direct). Used to
  /// surface devices that are visible on the local network but not yet
  /// paired, so discovery never dead-ends for roster-unknown peers.
  final MeshBloc mesh;

  final DirectoryRepositoryContract directory;
  final IdentityCryptoService crypto;

  /// Bundle 108: auto-pairing over the local network (beacon channel).
  final PairingService pairing;

  /// Section title ("Nearby", or "People nearby" after a search miss).
  final String title;

  /// Text typed in the search box ('' = show everyone).
  final String filter;

  /// Bundle 267: an extra line under "Looking for LinkUp phones…" (Add
  /// Contact opens this section only after a search found no one).
  final String? waitLine;

  /// This account's user id — phones of the same account are hidden.
  final String selfUserId;

  /// Bundle 283: my first letter in the middle of the search scene.
  final String meInitial;

  const NearbyPeopleSection({
    super.key,
    required this.connectivity,
    required this.mesh,
    required this.directory,
    required this.crypto,
    required this.pairing,
    this.title = 'Nearby',
    this.filter = '',
    this.selfUserId = '',
    this.waitLine,
    this.meInitial = '',
  });

  @override
  State<NearbyPeopleSection> createState() => _NearbyPeopleSectionState();
}

class _NearbyPeopleSectionState extends State<NearbyPeopleSection>
    with SingleTickerProviderStateMixin {
  // Bundle 125: node ids of phones already paired with this device — a
  // paired phone inside the DISCOVERED list must never offer "Pair" again.
  Set<String> _trustedIds = const <String>{};
  // Bundle 190: false until the paired list is read once - until then a
  // linked phone still counts as a contact (no flash of contact cards).
  bool _trustedLoaded = false;
  // Bundle 154: blocked people never show on Nearby.
  Set<String> _blockedIds = const <String>{};
  StreamSubscription<String>? _pairedSub;

  /// Bundle 196 (12b): "wait" reply from a private profile.
  StreamSubscription<String>? _waitingSub;
  // Bundle 126: burst-duplicated accept packets used to fire the "paired"
  // stream once per copy. Dedupe by a short window.
  DateTime? _lastPairHandledAt;

  // Bundle 170: nearby permission (null = not checked yet).
  bool? _permission;

  // Bundle 226 (B5): the Bluetooth cards (× hides one for 7 days).
  static const String _bleAllowHideKey = 'ble_card_allow_hidden_until';
  static const String _bleBlockedKey = 'ble_perm_blocked';
  int _bleAllowHiddenUntil = 0;
  bool _bleBlocked = false;
  bool _bleAsking = false;

  // Bundle 170: the "someone found" moment.
  late final AnimationController _found = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  final DateTime _openedAt = DateTime.now();
  bool _sawLooking = false;
  bool _celebrating = false;
  String _celebrateInitial = '';

  // Bundle 256 E6-E9: chips, Wi-Fi card, phones kept 2 min, NEARBY_LIST.
  Timer? _tick256;
  bool? _radioOn256;
  final NearbyKept256<MeshPeer> _kept256 = NearbyKept256<MeshPeer>();
  String _listLine256 = '';
  int _listLoggedAt256 = 0;

  /// Wi-Fi radio off = off; else the network watcher (null = not known).
  bool? get _wifi256 => _radioOn256 == false ? false : ServerReach.instance.wifi;

  Future<void> _onTick256() async {
    bool? radio;
    try {
      radio = (await WifiRadioControlService().status()).enabled;
    } catch (_) {
      radio = null; // no channel (tests) - the watcher alone decides
    }
    if (!mounted) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_listLine256.isNotEmpty && now - _listLoggedAt256 >= 30000) {
      _listLoggedAt256 = now;
      AppLogger.info('NEARBY_LIST', detail: _listLine256);
    }
    if (radio != _radioOn256 || !_kept256.isEmpty) {
      setState(() => _radioOn256 = radio);
    }
  }

  Future<void> _openWifi256() async {
    AppLogger.info('NEARBY', detail: 'WIFI_CARD open_settings');
    try {
      await WifiRadioControlService().openSettings();
    } catch (_) {}
  }

  /// Bundle 283 (mock F): "Wi-Fi is off" - the button only opens the
  /// Android Wi-Fi settings (the app never turns Wi-Fi on).
  Widget _wifiCard256(BuildContext context) => WarnCard283(
        key: const ValueKey<String>('nearby_wifi_card_256'),
        kind: WarnKind283.wifi,
        title: 'Wi-Fi is off',
        text: 'Turn it on to find phones near you',
        action: 'Turn on',
        onPressed: _openWifi256,
      );

  Widget _keptCard256(({String id, String? name, MeshPeer peer, int ageMs}) k) {
    return Opacity(
      key: ValueKey<String>('nearby_kept_${k.id}'),
      opacity: .6,
      child: _NearbyCard(
        initial: initialOf(k.name ?? nearbyUnknownName),
        title: k.name ?? nearbyUnknownName,
        subtitle: nearbySeenLabel256(k.ageMs),
        action: GradientChip283(
          text: 'Add friend',
          onPressed: () => _pairSheet(k.peer),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    unawaited(_startSearch(askPermission: false));
    unawaited(_refreshTrusted());
    unawaited(_loadBle()); // Bundle 226
    _pairedSub = widget.pairing.paired.listen(_onPaired);
    // Bundle 196 (12b): while Nearby is open, an accepted request opens
    // the chat; "wait" shows a short note.
    FriendRequestBook.instance.nearbyOnScreen++;
    _waitingSub = widget.pairing.waiting.listen(_onWaiting);
    unawaited(_onTick256());
    _tick256 = Timer.periodic(const Duration(seconds: 5), (_) => unawaited(_onTick256()));
  }

  void _onWaiting(String name) {
    if (!mounted) return;
    final who = name.trim().isEmpty ? 'They' : name.trim();
    _snack('Request sent. $who needs to accept.');
  }

  @override
  void dispose() {
    if (FriendRequestBook.instance.nearbyOnScreen > 0) {
      FriendRequestBook.instance.nearbyOnScreen--;
    }
    unawaited(_waitingSub?.cancel());
    _waitingSub = null;
    unawaited(_pairedSub?.cancel());
    _pairedSub = null;
    _tick256?.cancel();
    _found.dispose();
    super.dispose();
  }

  /// Bundle 170: the search starts by itself only when the permission is
  /// already granted — otherwise the Allow card asks (no automatic popup).
  Future<void> _startSearch({required bool askPermission}) async {
    final c = widget.connectivity;
    bool granted;
    try {
      granted = await c.hasWifiDirectPermission();
    } catch (_) {
      granted = false;
    }
    if (!granted && askPermission) {
      try {
        await c.requestWifiDirectEnable();
        granted = await c.hasWifiDirectPermission();
      } catch (_) {}
    }
    // Bundle 283 (owner chose a): no Bluetooth card any more - the
    // Bluetooth permission is asked with the same Allow tap ("Nearby
    // devices" on Android 12+; 13+ grants it with no second pop-up).
    if (askPermission) await _askBle283();
    if (!mounted) return;
    setState(() => _permission = granted);
    if (granted) unawaited(c.discoverWifiDirect());
  }

  /// Bundle 283: Bluetooth still needs its OK (Android 12+, not answered
  /// "never" in the last 7 days) -> the one "Find phones near you" card.
  bool get _bleNeedsOk283 {
    if (NearbyBleActions.control == null) return false;
    final status = NearbyBleStatus.instance;
    return bleCardFor(
          state: status.state,
          sdk: status.sdk,
          wifiCardShown: false,
          now: DateTime.now().millisecondsSinceEpoch,
          allowHiddenUntil: _bleAllowHiddenUntil,
        ) ==
        BleCard.allow;
  }

  /// Bundle 283: asks the Bluetooth permission (no pop-up by itself: only
  /// from the Allow tap). Denied -> the card rests 7 days; "Don't ask
  /// again" before -> the app settings open instead.
  Future<void> _askBle283() async {
    final control = NearbyBleActions.control;
    if (control == null || _bleAsking || !_bleNeedsOk283) return;
    if (_bleBlocked) {
      AppLogger.info('NEARBY', detail: 'BLE_PERM open_settings');
      try {
        await control.openBluetoothSettings(app: true);
      } catch (_) {}
      await _bleRest283();
      return;
    }
    _bleAsking = true;
    try {
      AppLogger.info('NEARBY', detail: 'BLE_PERM with_nearby');
      final r = await control
          .askBlePermission()
          .timeout(const Duration(seconds: 60));
      NearbyBleStatus.instance.updateFrom(r);
      if (r['blocked'] == true) {
        _bleBlocked = true;
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool(_bleBlockedKey, true);
        } catch (_) {}
      }
      if (_bleNeedsOk283) await _bleRest283();
    } catch (_) {
      // No answer: the card stays; the next tap asks again.
    } finally {
      _bleAsking = false;
    }
  }

  Future<void> _bleRest283() async {
    final until = DateTime.now().millisecondsSinceEpoch + BleRules.cardHideMs;
    if (mounted) setState(() => _bleAllowHiddenUntil = until);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_bleAllowHideKey, until);
    } catch (_) {}
  }

  Future<void> _refreshTrusted() async {
    try {
      final ids = await widget.pairing.trustedNodeIds();
      if (mounted) {
        setState(() {
          _trustedIds = ids;
          _trustedLoaded = true;
        });
      }
    } catch (_) {}
    try {
      final blocked = await widget.pairing.blockedNodeIds();
      if (mounted) setState(() => _blockedIds = blocked);
    } catch (_) {}
  }

  /// Bundle 154: one place that decides which cards Nearby shows.
  // Bundle 155: who-is-who tag id per node id (cached SHA-256 prefix).
  final Map<String, String> _tagIds = <String, String>{};
  String _tagIdOf(String nodeId) => _tagIds[nodeId] ??= NearbyTag.idFor(nodeId);

  NearbyListPlan _plan(MeshState meshState, List<WifiDirectPeer> wifiPeers) {
    final meshPeers = meshState.peers.values.toList();
    // Bundle 190: a short link drop no longer hides the phone.
    final discovered = nearbyDiscoveredIds(
      [
        for (final p in meshPeers)
          (id: p.nodeId, state: p.state, lastSeenAt: p.lastSeenAt),
      ],
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );
    final live = meshPeers.where((p) =>
        p.state == 'CONNECTED' ||
        p.state == 'AVAILABLE' ||
        p.state == 'CONNECTING');
    return planNearbyList(
      discoveredNodeIds: discovered,
      liveNodeIds: [for (final p in live) p.nodeId],
      trustedIds: _trustedIds,
      blockedIds: _blockedIds,
      liveMeansContact: !_trustedLoaded,
      wifiAddresses: [for (final p in wifiPeers) p.address.trim().toLowerCase()],
      tagIdByAddress: {
        for (final e in NearbyTagRegistry.instance.byAddress.entries)
          e.key: e.value.idHash,
      },
      hashOf: _tagIdOf,
      friendWifiAddresses: FriendNearbyHints.instance.wdAddresses,
      missingFriends: FriendNearbyHints.instance.missingRecent,
    );
  }

  List<String> _unpairedDiscoveredIds() =>
      _plan(widget.mesh.state, const <WifiDirectPeer>[]).addableNodeIds;

  /// Bundle 125: pairing succeeded (this phone's "_paired" event fired just
  /// as the global toast shows "Connected with …").
  /// Bundle 154: Nearby now STAYS open so several people can be added in a
  /// row — the new contact simply disappears from the list (the global
  /// "Connected with … — say hi!" toast confirms it).
  void _onPaired(String displayName) {
    if (!mounted) return;
    final now = DateTime.now();
    final last = _lastPairHandledAt;
    if (last != null && now.difference(last) < const Duration(seconds: 5)) {
      return; // burst duplicate of the pairing we just reacted to
    }
    _lastPairHandledAt = now;
    try {
      unawaited(_refreshTrusted());
    } catch (_) {
      // Never let a pairing-completion reaction take the app down — the
      // contact is already saved; worst case the user navigates back by hand.
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    LinkToast.show(context, message, kind: LinkToast.guess(message));
  }

  /// Bundle 118: one-tap Pair for a Wi-Fi Direct peer — the transport link
  /// is established silently (permissions/support preflight still run, errors
  /// surface through the bloc listener) and, when the same phone is already
  /// beacon-visible on the LAN (the common case on shared Wi-Fi), the pair
  /// request fires immediately. Users never see a separate Connect step.
  Future<void> _pairWithWifiPeer(WifiDirectPeer peer) async {
    AppLogger.info('PAIR_UI', detail: 'stage=pair_button peer=${peer.name}');
    final c = widget.connectivity;
    if (!await c.isWifiDirectSupported()) {
      _snack('This phone cannot reach that phone directly.');
      return;
    }
    if (!await c.hasWifiDirectPermission()) {
      await c.requestWifiDirectEnable();
      _snack(
          'Allow the "Nearby devices" permission, then tap Add friend again.');
      return;
    }
    _snack('Waiting for this phone…');
    // Bundle 154 (F6): remember which unpaired phones were already visible,
    // so the phone that appears right after this tap gets the request —
    // already-paired phones nearby no longer block pairing.
    final before = _unpairedDiscoveredIds().toSet();
    // Bundle 155: a tagged phone is matched exactly by its tag id.
    final wanted = NearbyTagRegistry.instance.tagFor(peer.address)?.idHash;
    // Bundle 177 (Q6): silent join only (no "Accept invitation?" pop-up).
    unawaited(c.nearbyAddFriendTap(peer));
    String? target = wanted == null
        ? pickPairTarget(
            unpairedBefore: before, unpairedNow: _unpairedDiscoveredIds())
        : pickPairTarget(
            unpairedBefore: before,
            unpairedNow: _unpairedDiscoveredIds(),
            wantedTagId: wanted,
            hashOf: _tagIdOf);
    if (wanted != null && target == null) {
      // Bundle 157: the other phone joins the shared group by itself; give
      // it up to ~40 s to show up.
      for (var i = 0; i < 20 && mounted; i++) {
        await Future<void>.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        target = pickPairTarget(
            unpairedBefore: before,
            unpairedNow: _unpairedDiscoveredIds(),
            wantedTagId: wanted,
            hashOf: _tagIdOf);
        if (target != null) break;
      }
    } else if (wanted == null && (target == null || before.contains(target))) {
      // Give the tapped phone up to ~12 s to show up on the local network.
      for (var i = 0; i < 6 && mounted; i++) {
        await Future<void>.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        final now = _unpairedDiscoveredIds();
        final fresh = now.where((id) => !before.contains(id)).toList();
        if (fresh.length == 1) {
          target = fresh.first;
          break;
        }
        if (fresh.length > 1) {
          target = null;
          break;
        }
        target = pickPairTarget(unpairedBefore: before, unpairedNow: now);
      }
    }
    if (!mounted) return;
    if (target == null) {
      AppLogger.warning('PAIR_UI',
          detail: 'PAIR_AMBIGUOUS count=${_unpairedDiscoveredIds().length}');
      if (_unpairedDiscoveredIds().isNotEmpty) {
        _snack('Tap Add friend next to the phone you want to add.');
      }
      return;
    }
    MeshPeer? meshPeer;
    for (final p in widget.mesh.state.peers.values) {
      if (p.nodeId == target) {
        meshPeer = p;
        break;
      }
    }
    if (meshPeer != null) await _requestPair(meshPeer);
  }

  /// Bundle 108: ask the discovered peer to pair — a signed identity packet
  /// rides the LAN beacon channel; the other phone shows Accept/Connect.
  /// Bundle 194: already my friend -> no add, no toast, open the chat.
  Future<bool> _openIfFriend(String nodeId) async {
    final hello = FriendHelloService.instance;
    if (hello == null) return false;
    final userId = PresenceHub.instance.userOf(nodeId) ?? '';
    if (userId.isEmpty || !await hello.isFriend(userId)) return false;
    if (!mounted) return true;
    await hello.openExistingChat(
        deviceId: nodeId,
        displayName: _personName(nodeId) ?? '',
        source: 'nearby');
    return true;
  }

  Future<void> _requestPair(MeshPeer peer) async {
    if (await _openIfFriend(peer.nodeId)) return; // Bundle 194
    if (!mounted) return;
    AppLogger.info('FRIEND_ADD_TAP', detail: 'source=nearby already=n');
    // Bundle 115: every stage of the tap chain is loud. Anything that throws
    // before this print line-by-line scaffold runs means the tap never left
    // the sheet — it lands in the console as PAIR_TAP lines either way.
    AppLogger.info('PAIR_TAP', detail: 'stage=handler node=${peer.nodeId}');
    Object? lastError;
    for (var attempt = 0; attempt < 4; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(const Duration(seconds: 3));
        if (!mounted) return;
      }
      try {
        AppLogger.info('PAIR_TAP', detail: 'stage=calling_requestPair attempt=${attempt + 1}');
        await widget.pairing.requestPair(peer.nodeId);
        AppLogger.info('PAIR_TAP', detail: 'stage=requestPair_returned_ok');
        // Bundle 177 (7.3): no accept box any more; "<name> added" follows.
        _snack('Adding ${_personName(peer.nodeId) ?? 'this phone'}…');
        return;
      } catch (error) {
        lastError = error;
        final text = cleanBlocError(error);
        final lower = text.toLowerCase();
        final endpointPending = lower.contains('not visible') ||
            lower.contains('not configured') ||
            lower.contains('wait for it');
        // Bundle 224 (C2): "not visible yet" is a wait, not a fault (INFO).
        if (endpointPending) {
          AppLogger.info('PAIR_TAP', detail: 'stage=caught error=$error');
        } else {
          AppLogger.warning('PAIR_TAP', detail: 'stage=caught error=$error');
        }
        if (!endpointPending || attempt == 3) {
          _snack(text);
          return;
        }
      }
    }
    if (lastError != null) _snack(cleanBlocError(lastError));
  }

  /// Bundle 118 rev2: slim confirmation sheet after the Pair tap — avatar,
  /// one id line WITH a copy affordance (the icon the old sheet lost), one
  /// transport chip, one primary action, one cancel. No paragraphs.
  Future<void> _pairSheet(MeshPeer peer) async {
    if (await _openIfFriend(peer.nodeId)) return; // Bundle 194
    if (!mounted) return;
    final scheme = Theme.of(context).colorScheme;
    // Reuse the wifi-direct peer name when it is the only visible phone —
    // it is almost certainly the same device discovered over LAN.
    final wifiPeers = widget.connectivity.state.snapshot.wifiPeers;
    // Bundle 154: only when no paired contact is nearby either — otherwise
    // the single Wi-Fi Direct name may belong to that contact.
    final soloPlan = _plan(widget.mesh.state, wifiPeers);
    // Bundle 170: the person's real name when known.
    final knownName = _personName(peer.nodeId) ??
        (wifiPeers.length == 1 &&
                soloPlan.pairedNearbyCount == 0 &&
                soloPlan.addableNodeIds.length == 1 &&
                wifiPeers.first.name.isNotEmpty
            ? wifiPeers.first.name
            : null);
    final displayName = knownName ?? 'this phone';
    final send = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(
            LocalLinkSpacing.lg, 0, LocalLinkSpacing.lg, LocalLinkSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: scheme.primaryContainer,
              child: knownName == null
                  ? Icon(Icons.phone_android_rounded,
                      color: scheme.onPrimaryContainer)
                  : Text(initialOf(knownName),
                      style: TextStyle(
                          fontSize: 20, color: scheme.onPrimaryContainer)),
            ),
            const SizedBox(height: 12),
            Text('Add $displayName as a friend?',
                style: Theme.of(sheetContext).textTheme.titleMedium,
                textAlign: TextAlign.center),
            // Bundle 263 (B6): no phone id row (not useful to a normal user).
            const SizedBox(height: 4),
            Chip(
              // Bundle 170: no transport words — just Nearby.
              label: const Text('Nearby'),
              visualDensity: VisualDensity.compact,
              side: BorderSide.none,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
            const SizedBox(height: LocalLinkSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.of(sheetContext).pop(true),
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                label: const Text('Add friend'),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(sheetContext).pop(false),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
    if (send == true && mounted) {
      AppLogger.info('PAIR_SHEET', detail: 'confirmed node=${peer.nodeId}');
      await _requestPair(peer);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<ConnectivityBloc, ConnectivityState>(
      bloc: widget.connectivity,
      listenWhen: (prev, next) =>
          next.error != null && next.error != prev.error,
      listener: (context, state) => LinkToast.show(context, friendlyErrorMessage(state.error!), kind: LinkToastKind.error),
      child: BlocBuilder<ConnectivityBloc, ConnectivityState>(
        bloc: widget.connectivity,
        builder: (context, state) => ListenableBuilder(
          // Bundle 148: names + live status come from PresenceHub.
          listenable: Listenable.merge(
              [PresenceHub.instance, NearbyTagRegistry.instance, _found]),
          builder: (context, _) => BlocBuilder<MeshBloc, MeshState>(
            bloc: widget.mesh,
            builder: (context, meshState) =>
                _content(context, state, meshState),
          ),
        ),
      ),
    );
  }

  /// Bundle 154 + 170: the people you can still add (paired, blocked and
  /// your own other phones are hidden).
  List<_NearbyEntry> _entries(MeshState meshState, List<WifiDirectPeer> peers) {
    final plan = _plan(meshState, peers);
    final byId = <String, MeshPeer>{
      for (final p in meshState.peers.values) p.nodeId: p,
    };
    final self = widget.selfUserId;
    final out = <_NearbyEntry>[];
    for (final id in plan.addableNodeIds) {
      final peer = byId[id];
      if (peer == null) continue;
      if (self.isNotEmpty && PresenceHub.instance.userOf(id) == self) continue;
      final name = _personName(id) ??
          (peers.length == 1 &&
                  plan.addableNodeIds.length == 1 &&
                  plan.pairedNearbyCount == 0 &&
                  peers.first.name.isNotEmpty
              ? peers.first.name
              : null);
      out.add(_NearbyEntry(key: 'm:$id', name: name, mesh: peer));
    }
    for (final p in peers) {
      final address = p.address.trim().toLowerCase();
      if (!plan.wifiAddresses.contains(address)) continue;
      out.add(_NearbyEntry(
          key: 'w:$address', name: p.name.isEmpty ? null : p.name, wifi: p));
    }
    return out;
  }

  Widget _content(
      BuildContext context, ConnectivityState state, MeshState meshState) {
    final peers = state.snapshot.wifiPeers;
    final entries = _entries(meshState, peers);
    final filter = widget.filter.trim();

    // Typing: only the people whose name matches; nothing at all otherwise.
    if (filter.isNotEmpty) {
      final shown = [
        for (final e in entries)
          if (nearbyNameMatches(e.name, filter)) e,
      ];
      if (shown.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context, live: true),
          for (final e in shown) _card(state, e),
        ],
      );
    }

    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final any = entries.isNotEmpty;
    if (!any) {
      _sawLooking = true;
    } else if (_sawLooking && !_celebrating) {
      _sawLooking = false;
      // A person found right as the screen opens goes straight to the list;
      // one found after a little search gets the "found" moment.
      final waited = DateTime.now().difference(_openedAt) >
          const Duration(milliseconds: 1200);
      if (waited && !reduceMotion) {
        _celebrating = true;
        _celebrateInitial = initialOf(entries.first.name);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _found.forward(from: 0).whenCompleteOrCancel(() {
            if (mounted) setState(() => _celebrating = false);
          });
        });
      }
    }

    final plan = _plan(meshState, peers);
    // Bundle 256 E8: phones that just left stay 2 min, greyed.
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    _kept256.saw([
      for (final e in entries)
        if (e.mesh != null) (id: e.mesh!.nodeId, name: e.name, peer: e.mesh!),
    ], nowMs);
    final kept = _kept256.kept(nowMs, {
      for (final e in entries)
        if (e.mesh != null) e.mesh!.nodeId,
      ..._trustedIds,
      ..._blockedIds,
    });
    final wifi = _wifi256;
    final bleState = NearbyBleStatus.instance.state;
    _listLine256 = nearbyListLog256(
      shown: entries.length,
      lan: entries.where((e) => (e.mesh?.transport ?? '').contains('lan')).length,
      wd: entries.where((e) => e.wifi != null || (e.mesh?.transport ?? '').contains('direct')).length,
      ble: entries.where((e) => (e.mesh?.transport ?? '').contains('ble')).length,
      kept: kept.length,
      wifi: wifi,
      bleState: bleState,
    );
    // Bundle 283 (mock 283 C-F): no chips and no Bluetooth cards; a card
    // only when something is needed (Wi-Fi off / the OK missing).
    final needsOk = _permission == false || _bleNeedsOk283;
    final searchingNow = _permission != false && wifi != false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context, live: searchingNow),
        // Bundle 256 E7: Wi-Fi went off (only opens Android Wi-Fi settings).
        if (wifi == false) SlideIn283(child: _wifiCard256(context)),
        if (needsOk)
          SlideIn283(
            delay: const Duration(milliseconds: 120),
            child: _permissionCard(context),
          ),
        if (_celebrating)
          _lookingBox(context,
              foundProgress: _found.value, initial: _celebrateInitial)
        else if (!any && kept.isNotEmpty) ...[
          for (final k in kept) _keptCard256(k),
        ] else if (!any) ...[
          if (plan.emptyState == NearbyEmptyState.everyoneAdded)
            const SlideIn283(
              delay: Duration(milliseconds: 150),
              child: QuietLine283('Everyone nearby is already in your contacts'),
            )
          else if (searchingNow)
            _lookingBox(context),
        ] else ...[
          for (final e in entries) _card(state, e),
          for (final k in kept) _keptCard256(k),
        ],
      ],
    );
  }

  /// Bundle 283 (mock `.sec`): small grey capitals + live "Searching".
  Widget _header(BuildContext context, {required bool live}) =>
      SectionTitle283(widget.title, live: live);

  /// Bundle 283 (mock 283 D/E): the new search scene. [foundProgress] > 0 =
  /// the curved line reaches the person, "Found someone!", then the card.
  Widget _lookingBox(BuildContext context,
      {double foundProgress = 0, String initial = ''}) {
    final p = LinkKit.of(context);
    final found = initial.isNotEmpty && foundProgress > .5;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NearbyScene283(
          found: foundProgress,
          foundInitial: initial,
          meInitial: widget.meInitial,
        ),
        const SizedBox(height: 14),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: found
              ? Text('Found someone!',
                  key: const ValueKey('nearby_found_283'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: p.ok))
              : const LookingText283('Looking for phones near you',
                  key: ValueKey('nearby_looking_283')),
        ),
        if (!found) ...[
          const SizedBox(height: 4),
          Text('Keep Wi-Fi on, on both phones',
              key: const ValueKey('nearby_wait_267'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: p.muted)),
        ],
      ],
    );
  }

  /// Bundle 283 (mock F): one card for the Nearby OK (Wi-Fi Direct and,
  /// on Android 12+, Bluetooth - both in "Nearby devices").
  Widget _permissionCard(BuildContext context) => WarnCard283(
        key: const ValueKey<String>('nearby_allow_card_283'),
        kind: WarnKind283.nearby,
        title: 'Find phones near you',
        text: 'LinkUp needs your OK once',
        action: 'Allow',
        onPressed: () => _startSearch(askPermission: true),
      );

  // ------------------------------------- Bundle 226 (B5) Bluetooth state
  // ---------------------------------------------- Bundle 226 (B5) cards

  Future<void> _loadBle() async {
    final control = NearbyBleActions.control;
    if (control == null) return;
    try {
      NearbyBleStatus.instance.updateFrom(await control.bleStatus());
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _bleAllowHiddenUntil = prefs.getInt(_bleAllowHideKey) ?? 0;
        _bleBlocked = prefs.getBool(_bleBlockedKey) ?? false;
      });
    } catch (_) {}
  }

  Widget _card(ConnectivityState state, _NearbyEntry e) {
    final mesh = e.mesh;
    final wifi = e.wifi;
    final Widget action;
    if (mesh != null) {
      // Bundle 196 (12b.4): "Requested" (disabled) for 24 h after a private
      // person answered "wait"; then back to "Add friend".
      action = ListenableBuilder(
        listenable: FriendRequestBook.instance,
        builder: (context, _) => FriendRequestBook.instance.isSent(mesh.nodeId)
            ? GradientChip283(
                key: ValueKey('nearby_requested_${mesh.nodeId}'),
                text: 'Requested',
                icon: Icons.schedule_rounded,
                onPressed: null,
              )
            : GradientChip283(
                text: 'Add friend',
                onPressed: () => _pairSheet(mesh),
              ),
      );
    } else {
      action = state.busy
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2))
          : GradientChip283(
              text: 'Add friend',
              onPressed: wifi == null ? null : () => _pairWithWifiPeer(wifi),
            );
    }
    // Bundle 170: each new card slides up into the list.
    return TweenAnimationBuilder<double>(
      key: ValueKey<String>(e.key),
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 550),
      curve: AddUi283.easeOut,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 26 * (1 - v)), child: child),
      ),
      child: _NearbyCard(
        initial: initialOf(e.name ?? nearbyUnknownName),
        title: e.name ?? nearbyUnknownName,
        subtitle: nearbyCardSubtitle,
        action: action,
      ),
    );
  }
}

/// Bundle 170: one row of the Nearby list.
class _NearbyEntry {
  final String key;
  final String? name;
  final MeshPeer? mesh;
  final WifiDirectPeer? wifi;
  const _NearbyEntry({required this.key, this.name, this.mesh, this.wifi});
}

/// Bundle 148: node id == device id, so a paired phone shows its person.
String? _personName(String nodeId) => PresenceHub.instance.nameOf(nodeId);

/// Bundle 118 + 170: single compact card per nearby phone — the person's
/// initial, their name, one short subtitle and the Pair button.
class _NearbyCard extends StatelessWidget {
  final String initial;
  final String title;
  final String subtitle;
  final Widget? action;
  const _NearbyCard({
    required this.initial,
    required this.title,
    required this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) => PersonCard283(
        avatar: LetterAvatar283(
            name: title, initial: initial, gradient: AddUi283.purpleGradient),
        title: title,
        subtitle: Text(subtitle),
        trailing: action,
      );
}
