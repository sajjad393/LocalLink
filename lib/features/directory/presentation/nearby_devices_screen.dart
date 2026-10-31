import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:locallink/core/presence/presence_hub.dart';
import 'package:locallink/core/bloc/bloc_utils.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/core/widgets/error_toast.dart';
import 'package:locallink/features/connectivity/bloc/connectivity_bloc.dart';
import 'package:locallink/features/connectivity/bloc/mesh_bloc.dart';
import 'package:locallink/features/connectivity/data/models/nearby_tag.dart';
import 'package:locallink/features/connectivity/data/models/wifi_direct_models.dart';
import 'package:locallink/features/directory/domain/directory_repository_contract.dart';
import 'package:locallink/features/directory/data/services/pairing_service.dart';
import 'package:locallink/features/directory/presentation/nearby_list_plan.dart';
import 'package:locallink/features/directory/presentation/nearby_search_animation.dart';
import 'package:locallink/features/directory/presentation/profile_view_rules.dart';

/// Bundle 170: the Nearby list now lives INSIDE Add Contact (the separate
/// Nearby screen and its button on Contacts are gone). This section shows
/// the phones you can still add, under the search box:
///
/// * [filter] narrows the list while the user types (real names only);
///   when nothing matches the section hides itself.
/// * Nobody found yet → the mesh search animation (replaces the radar).
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

  /// This account's user id — phones of the same account are hidden.
  final String selfUserId;

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
  });

  @override
  State<NearbyPeopleSection> createState() => _NearbyPeopleSectionState();
}

class _NearbyPeopleSectionState extends State<NearbyPeopleSection>
    with SingleTickerProviderStateMixin {
  // Bundle 125: node ids of phones already paired with this device — a
  // paired phone inside the DISCOVERED list must never offer "Pair" again.
  Set<String> _trustedIds = const <String>{};
  // Bundle 154: blocked people never show on Nearby.
  Set<String> _blockedIds = const <String>{};
  StreamSubscription<String>? _pairedSub;
  // Bundle 126: burst-duplicated accept packets used to fire the "paired"
  // stream once per copy. Dedupe by a short window.
  DateTime? _lastPairHandledAt;

  // Bundle 170: nearby permission (null = not checked yet).
  bool? _permission;

  // Bundle 170: the "someone found" moment.
  late final AnimationController _found = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  final DateTime _openedAt = DateTime.now();
  bool _sawLooking = false;
  bool _celebrating = false;
  String _celebrateInitial = '';

  @override
  void initState() {
    super.initState();
    unawaited(_startSearch(askPermission: false));
    unawaited(_refreshTrusted());
    _pairedSub = widget.pairing.paired.listen(_onPaired);
  }

  @override
  void dispose() {
    unawaited(_pairedSub?.cancel());
    _pairedSub = null;
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
    if (!mounted) return;
    setState(() => _permission = granted);
    if (granted) unawaited(c.discoverWifiDirect());
  }

  Future<void> _refreshTrusted() async {
    try {
      final ids = await widget.pairing.trustedNodeIds();
      if (mounted) setState(() => _trustedIds = ids);
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
    final discovered = meshPeers
        .where((p) => p.state == 'DISCOVERED')
        .toList(growable: false)
      ..sort((a, b) => (b.lastSeenAt ?? 0).compareTo(a.lastSeenAt ?? 0));
    final live = meshPeers.where((p) =>
        p.state == 'CONNECTED' ||
        p.state == 'AVAILABLE' ||
        p.state == 'CONNECTING');
    return planNearbyList(
      discoveredNodeIds: [for (final p in discovered) p.nodeId],
      liveNodeIds: [for (final p in live) p.nodeId],
      trustedIds: _trustedIds,
      blockedIds: _blockedIds,
      wifiAddresses: [for (final p in wifiPeers) p.address.trim().toLowerCase()],
      tagIdByAddress: {
        for (final e in NearbyTagRegistry.instance.byAddress.entries)
          e.key: e.value.idHash,
      },
      hashOf: _tagIdOf,
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
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Bundle 118: one-tap Pair for a Wi-Fi Direct peer — the transport link
  /// is established silently (permissions/support preflight still run, errors
  /// surface through the bloc listener) and, when the same phone is already
  /// beacon-visible on the LAN (the common case on shared Wi-Fi), the pair
  /// request fires immediately. Users never see a separate Connect step.
  Future<void> _pairWithWifiPeer(WifiDirectPeer peer) async {
    AppLogger.warning('PAIR_UI', detail: 'stage=pair_button peer=${peer.name}');
    final c = widget.connectivity;
    if (!await c.isWifiDirectSupported()) {
      _snack('This phone does not support Wi-Fi Direct.');
      return;
    }
    if (!await c.hasWifiDirectPermission()) {
      await c.requestWifiDirectEnable();
      _snack(
          'Allow the "Nearby devices" permission, then tap Pair again.');
      return;
    }
    _snack('Asking the other phone to accept…');
    // Bundle 154 (F6): remember which unpaired phones were already visible,
    // so the phone that appears right after this tap gets the request —
    // already-paired phones nearby no longer block pairing.
    final before = _unpairedDiscoveredIds().toSet();
    // Bundle 155: a tagged phone is matched exactly by its tag id.
    final wanted = NearbyTagRegistry.instance.tagFor(peer.address)?.idHash;
    unawaited(c.connectWifiDirect(peer));
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
        _snack('Tap Pair next to the phone you want to add.');
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
  Future<void> _requestPair(MeshPeer peer) async {
    // Bundle 115: every stage of the tap chain is loud. Anything that throws
    // before this print line-by-line scaffold runs means the tap never left
    // the sheet — it lands in the console as PAIR_TAP lines either way.
    AppLogger.warning('PAIR_TAP', detail: 'stage=handler node=${peer.nodeId}');
    Object? lastError;
    for (var attempt = 0; attempt < 4; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(const Duration(seconds: 3));
        if (!mounted) return;
      }
      try {
        AppLogger.warning('PAIR_TAP', detail: 'stage=calling_requestPair attempt=${attempt + 1}');
        await widget.pairing.requestPair(peer.nodeId);
        AppLogger.warning('PAIR_TAP', detail: 'stage=requestPair_returned_ok');
        _snack('Pair request sent — the other phone will be asked to accept.');
        return;
      } catch (error) {
        AppLogger.warning('PAIR_TAP', detail: 'stage=caught error=$error');
        lastError = error;
        final text = cleanBlocError(error);
        final lower = text.toLowerCase();
        final endpointPending = lower.contains('not visible') ||
            lower.contains('not configured') ||
            lower.contains('wait for it');
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
    final scheme = Theme.of(context).colorScheme;
    final tail = peer.nodeId.length > 8
        ? peer.nodeId.substring(peer.nodeId.length - 8)
        : peer.nodeId;
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
            Text('Pair with $displayName?',
                style: Theme.of(sheetContext).textTheme.titleMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text('device …$tail',
                      style: Theme.of(sheetContext).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis),
                ),
                IconButton(
                  tooltip: 'Copy device id',
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  onPressed: () async {
                    await Clipboard.setData(
                        ClipboardData(text: peer.nodeId));
                    if (sheetContext.mounted) {
                      ScaffoldMessenger.of(sheetContext).showSnackBar(
                        const SnackBar(content: Text('Device id copied')),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy_rounded),
                ),
              ],
            ),
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
                icon: const Icon(Icons.handshake_outlined, size: 18),
                label: const Text('Send pair request'),
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
      AppLogger.warning('PAIR_SHEET', detail: 'confirmed node=${peer.nodeId}');
      await _requestPair(peer);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<ConnectivityBloc, ConnectivityState>(
      bloc: widget.connectivity,
      listenWhen: (prev, next) =>
          next.error != null && next.error != prev.error,
      listener: (context, state) => ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyErrorMessage(state.error!)))),
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
          _header(context, dots: true),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context, dots: any && !_celebrating),
        if (_permission == false) _permissionCard(context),
        if (_celebrating)
          _lookingBox(context,
              foundProgress: _found.value, initial: _celebrateInitial)
        else if (!any) ...[
          if (plan.emptyState == NearbyEmptyState.everyoneAdded)
            _NearbyInfoCard(
              icon: Icons.how_to_reg_rounded,
              text: 'Everyone nearby is already in your contacts.',
              action: TextButton(
                onPressed: () => Navigator.maybePop(context),
                child: const Text('See contacts'),
              ),
            )
          else if (_permission != false)
            _lookingBox(context),
        ] else
          for (final e in entries) _card(state, e),
      ],
    );
  }

  Widget _header(BuildContext context, {required bool dots}) => Padding(
        padding: const EdgeInsets.only(
            top: LocalLinkSpacing.sm, bottom: LocalLinkSpacing.sm),
        child: Row(
          children: [
            Text(
              widget.title,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 8),
            if (dots) const NearbyMiniMesh(),
          ],
        ),
      );

  Widget _lookingBox(BuildContext context,
      {double foundProgress = 0, String initial = ''}) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 170,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: .35),
              borderRadius: BorderRadius.circular(20),
            ),
            child: NearbySearchAnimation(
              foundProgress: foundProgress,
              foundInitial: initial,
            ),
          ),
        ),
        const SizedBox(height: LocalLinkSpacing.sm),
        Text('Looking for LocalLink phones…',
            textAlign: TextAlign.center, style: text.titleSmall),
        const SizedBox(height: 2),
        Text('Both phones need Wi-Fi on',
            textAlign: TextAlign.center, style: text.bodySmall),
      ],
    );
  }

  Widget _permissionCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.tertiaryContainer.withValues(alpha: .6),
      child: ListTile(
        title: const Text('Allow nearby to see phones around you'),
        subtitle: const Text('Only asked when you tap Allow'),
        trailing: FilledButton(
          onPressed: () => _startSearch(askPermission: true),
          child: const Text('Allow'),
        ),
      ),
    );
  }

  Widget _card(ConnectivityState state, _NearbyEntry e) {
    final mesh = e.mesh;
    final wifi = e.wifi;
    final Widget action;
    if (mesh != null) {
      action = FilledButton.tonal(
        onPressed: () => _pairSheet(mesh),
        child: const Text('Pair'),
      );
    } else {
      action = FilledButton.tonal(
        onPressed: state.busy || wifi == null
            ? null
            : () => _pairWithWifiPeer(wifi),
        child: state.busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Text('Pair'),
      );
    }
    // Bundle 170: each new card slides up into the list.
    return TweenAnimationBuilder<double>(
      key: ValueKey<String>(e.key),
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 24 * (1 - v)), child: child),
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

/// Bundle 154: one simple info card (empty states) — icon, one line, and an
/// optional small action.
class _NearbyInfoCard extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? action;
  const _NearbyInfoCard({required this.icon, required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(LocalLinkSpacing.lg),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: scheme.secondaryContainer,
              child: Icon(icon, color: scheme.onSecondaryContainer),
            ),
            const SizedBox(width: LocalLinkSpacing.md),
            Expanded(child: Text(text)),
            if (action != null) action!,
          ],
        ),
      ),
    );
  }
}

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
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Text(initial)),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: action,
      ),
    );
  }
}
