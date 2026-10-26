import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:locallink/core/bloc/bloc_utils.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/core/widgets/error_toast.dart';
import 'package:locallink/core/widgets/messenger_section_header.dart';
import 'package:locallink/features/connectivity/bloc/connectivity_bloc.dart';
import 'package:locallink/features/connectivity/bloc/mesh_bloc.dart';
import 'package:locallink/features/connectivity/data/models/wifi_direct_models.dart';
import 'package:locallink/features/directory/domain/directory_repository_contract.dart';
import 'package:locallink/features/directory/presentation/add_contact_screen.dart';
import 'package:locallink/features/directory/data/services/pairing_service.dart';

class NearbyDevicesScreen extends StatefulWidget {
  final ConnectivityBloc connectivity;

  /// Mesh presence feed (LAN beacon discovery + Wi-Fi Direct). Used to
  /// surface devices that are visible on the local network but not yet
  /// paired, so discovery never dead-ends for roster-unknown peers.
  final MeshBloc mesh;

  /// Bundle 107: pairing becomes actionable — the Pair sheet can open Add
  /// contact (QR scan / search) directly instead of showing instructions.
  final DirectoryRepositoryContract directory;
  final IdentityCryptoService crypto;

  /// Bundle 108: auto-pairing over the local network (beacon channel).
  final PairingService pairing;

  const NearbyDevicesScreen({
    super.key,
    required this.connectivity,
    required this.mesh,
    required this.directory,
    required this.crypto,
    required this.pairing,
  });

  @override
  State<NearbyDevicesScreen> createState() => _NearbyDevicesScreenState();
}

class _NearbyDevicesScreenState extends State<NearbyDevicesScreen> with SingleTickerProviderStateMixin {
  late final AnimationController controller;

  @override
  void initState() {
    super.initState();
    final reduceMotion = WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    controller = AnimationController(vsync: this, duration: const Duration(seconds: 2));
    if (!reduceMotion) controller.repeat();
    widget.connectivity.discoverWifiDirect();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Bundle 107: Connect used to die invisibly — native errors were emitted
  /// into bloc state that this screen never rendered, and refresh() cleared
  /// them within a cycle. Now: preflight first (support/permission), show
  /// progress guidance, and let the BlocListener below surface failures.
  Future<void> _connect(WifiDirectPeer peer) async {
    final c = widget.connectivity;
    if (!await c.isWifiDirectSupported()) {
      _snack('This phone does not support Wi-Fi Direct.');
      return;
    }
    if (!await c.hasWifiDirectPermission()) {
      await c.requestWifiDirectEnable();
      _snack('Allow the "Nearby devices" permission, then tap Connect again.');
      return;
    }
    _snack('Connecting… the other phone is asked to accept once.');
    await c.connectWifiDirect(peer);
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

  void _openAddContact() {
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            AddContactScreen(repository: widget.directory, crypto: widget.crypto),
      ),
    );
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
      builder: (context, state) {
        final peers = state.snapshot.wifiPeers;
        return Scaffold(
          appBar: AppBar(title: const Text('Nearby')),
          body: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(LocalLinkSpacing.lg, LocalLinkSpacing.md, LocalLinkSpacing.lg, LocalLinkSpacing.xxl),
            children: [
              SizedBox(
                height: 230,
                child: Center(
                  child: AnimatedBuilder(
                    animation: controller,
                    builder: (_, __) => Stack(
                      alignment: Alignment.center,
                      children: [
                        if (!WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations)
                          for (int i = 0; i < 3; i++)
                            Container(
                              width: 96 + (i * 48) + 42 * math.sin((controller.value + i / 3) * math.pi * 2).abs(),
                              height: 96 + (i * 48) + 42 * math.sin((controller.value + i / 3) * math.pi * 2).abs(),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(.12), width: 2),
                              ),
                            ),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer,
                            shape: BoxShape.circle,
                          ),
                          child: const Padding(padding: EdgeInsets.all(24), child: Icon(Icons.smartphone_rounded, size: 36)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Text(
                peers.isEmpty ? 'Looking for nearby phones…' : '${peers.length} nearby ${peers.length == 1 ? 'phone' : 'phones'}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: LocalLinkSpacing.sm),
              Text(
                'Keep Wi-Fi Direct enabled to discover nearby LocalLink phones. You can message or call once a connection is available.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: LocalLinkSpacing.lg),
              if (peers.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(LocalLinkSpacing.lg),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                          child: Icon(Icons.radar_rounded,
                              color: Theme.of(context).colorScheme.onSecondaryContainer),
                        ),
                        const SizedBox(width: LocalLinkSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Nothing found yet',
                                  style: Theme.of(context).textTheme.titleSmall),
                              const SizedBox(height: 4),
                              Text(
                                'Make sure the other phone is nearby, has LocalLink open, and Wi-Fi is enabled.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ...peers.map(
                  (peer) => Card(
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.phone_android)),
                      title: Text(peer.name.isEmpty ? 'Nearby LocalLink phone' : peer.name),
                      // Android cannot hand us the peer's LocalLink device id
                      // over Wi-Fi Direct discovery, so automatic connect only
                      // happens when exactly one peer is visible. With several,
                      // connect explicitly here (product limitation, M3).
                      subtitle: Text(peers.length > 1
                          ? 'Several phones nearby — choose one to connect'
                          : 'Nearby connection available'),
                      trailing: FilledButton.tonal(
                        onPressed:
                            state.busy ? null : () => _connect(peer),
                        child: state.busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Connect'),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: LocalLinkSpacing.lg),
              _MeshNearbySection(
                mesh: widget.mesh,
                onAddContact: _openAddContact,
                onPairRequest: _requestPair,
              ),
            ],
          ),
        );
      },
    ),
    );
  }
}

/// Devices the mesh transport has discovered on the local network.
///
/// A device in DISCOVERED state has broadcast a valid beacon but is not in
/// this phone's roster: no session will be attempted, and no payload is
/// exchanged until both devices are paired contacts (profile-mirror trust
/// model). This section makes that discovery visible instead of letting it
/// dead-end silently.
class _MeshNearbySection extends StatelessWidget {
  final MeshBloc mesh;

  /// Bundle 107: opens Add contact so pairing is one tap, not instructions.
  final VoidCallback onAddContact;

  /// Bundle 108: in-band auto-pair attempt for the discovered peer.
  final void Function(MeshPeer peer) onPairRequest;
  const _MeshNearbySection({
    required this.mesh,
    required this.onAddContact,
    required this.onPairRequest,
  });

  static bool _isLive(String state) =>
      state == 'CONNECTED' || state == 'AVAILABLE' || state == 'CONNECTING';

  static String _when(int? lastSeenAt) {
    if (lastSeenAt == null || lastSeenAt <= 0) return 'seen just now';
    final age = DateTime.now().millisecondsSinceEpoch - lastSeenAt;
    if (age < 0) return 'seen just now';
    if (age < 60000) return 'seen ${(age / 1000).round()}s ago';
    return 'seen ${(age / 60000).round()}m ago';
  }

  static String _transportLabel(String transport) => switch (transport) {
        'lan' => 'same Wi-Fi / LAN',
        'wifi_direct' => 'Wi-Fi Direct',
        _ => 'local network',
      };

  static void _pairSheet(BuildContext context, MeshPeer peer,
      VoidCallback? onAddContact, void Function(MeshPeer peer) onPairRequest) {
    // Bundle 112 rev2: the QR "Add contact" button was removed from this
    // sheet (pair request is the one-tap path); QR adding stays under
    // Contacts → Add contact. Param kept so call sites don't churn.
    onAddContact;
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.all(LocalLinkSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pair this device', style: Theme.of(sheetContext).textTheme.titleMedium),
            const SizedBox(height: LocalLinkSpacing.md),
            SelectableText('Device id: ${peer.nodeId}',
                style: Theme.of(sheetContext).textTheme.bodyMedium),
            const SizedBox(height: LocalLinkSpacing.md),
            const Text(
              'LocalLink only opens sessions between paired contacts. Send a pair request and '
              'the other phone taps Connect once — both phones then add each other automatically, '
              'no QR codes needed. Messages and calls between you use the local network without '
              'the Internet. Scanning QR codes still works too (Add contact).',
            ),
            const SizedBox(height: LocalLinkSpacing.lg),
            Wrap(
              spacing: LocalLinkSpacing.sm,
              runSpacing: LocalLinkSpacing.sm,
              children: [
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    onPairRequest(peer);
                  },
                  icon: const Icon(Icons.handshake_outlined, size: 18),
                  label: const Text('Send pair request'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: peer.nodeId));
                    if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy device id'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MeshBloc, MeshState>(
      bloc: mesh,
      builder: (context, state) {
        final seen = state.peers.values.toList(growable: false)
          ..sort((a, b) => (b.lastSeenAt ?? 0).compareTo(a.lastSeenAt ?? 0));
        final live = seen.where((p) => _isLive(p.state)).toList(growable: false);
        final discovered =
            seen.where((p) => p.state == 'DISCOVERED').toList(growable: false);
        if (live.isEmpty && discovered.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const MessengerSectionHeader(title: 'On this network'),
            ...live.map(
              (peer) => Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        Theme.of(context).colorScheme.primaryContainer,
                    child: Icon(Icons.link,
                        color: Theme.of(context).colorScheme.primary),
                  ),
                  title: Text('LocalLink device ·…${peer.nodeId.length > 8 ? peer.nodeId.substring(peer.nodeId.length - 8) : peer.nodeId}'),
                  subtitle: Text(
                    '${peer.state.toLowerCase()} — ${_transportLabel(peer.transport)} · ${_when(peer.lastSeenAt)}.',
                  ),
                ),
              ),
            ),
            ...discovered.map(
              (peer) => Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.wifi_find)),
                  title: Text('LocalLink phone nearby ·…${peer.nodeId.length > 8 ? peer.nodeId.substring(peer.nodeId.length - 8) : peer.nodeId}'),
                  subtitle: Text(
                    'Found over ${_transportLabel(peer.transport)} — not yet paired: '
                    'messages stay unavailable until you pair.',
                  ),
                  trailing: FilledButton.tonal(
                    onPressed: () =>
                        _pairSheet(context, peer, onAddContact, onPairRequest),
                    child: const Text('Pair'),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
