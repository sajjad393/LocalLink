import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
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
    unawaited(c.connectWifiDirect(peer));
    final discovered = widget.mesh.state.peers.values
        .where((p) => p.state == 'DISCOVERED')
        .toList(growable: false);
    if (discovered.length == 1) {
      await _requestPair(discovered.first);
    }
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
                'Both phones need Wi-Fi on — pairing and chats work without the internet.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: LocalLinkSpacing.lg),
              BlocBuilder<MeshBloc, MeshState>(
                bloc: widget.mesh,
                builder: (context, meshState) {
                  final meshPeers = meshState.peers.values.toList();
                  final discovered = meshPeers
                      .where((p) => p.state == 'DISCOVERED')
                      .toList(growable: false)
                    ..sort((a, b) =>
                        (b.lastSeenAt ?? 0).compareTo(a.lastSeenAt ?? 0));
                  final live = meshPeers
                      .where((p) =>
                          p.state == 'CONNECTED' ||
                          p.state == 'AVAILABLE' ||
                          p.state == 'CONNECTING')
                      .toList(growable: false);
                  // Bundle 118: one card per phone. When a peer is visible on
                  // both Wi-Fi Direct and the LAN beacon (same phone seen
                  // twice), the LAN card wins — it carries the node id that
                  // pairing needs.
                  final wifiOnly = discovered.isEmpty ? peers : const [];
                  final nothingFound = wifiOnly.isEmpty &&
                      discovered.isEmpty &&
                      live.isEmpty;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (nothingFound)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(LocalLinkSpacing.lg),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: Theme.of(context)
                                      .colorScheme
                                      .secondaryContainer,
                                  child: Icon(Icons.radar_rounded,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSecondaryContainer),
                                ),
                                const SizedBox(width: LocalLinkSpacing.md),
                                const Expanded(
                                  child: Text(
                                    'Nothing found yet — keep LocalLink open on the other phone.',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else ...[
                        ...discovered.map(
                          (peer) => _NearbyCard(
                            icon: Icons.wifi_find_rounded,
                            title: peers.length == 1 && peers.first.name.isNotEmpty
                                ? peers.first.name
                                : 'LocalLink phone nearby ·…${peer.nodeId.length > 8 ? peer.nodeId.substring(peer.nodeId.length - 8) : peer.nodeId}',
                            subtitle:
                                'Same Wi-Fi / LAN — not paired yet',
                            action: FilledButton.tonal(
                              onPressed: () => _requestPair(peer),
                              child: const Text('Pair'),
                            ),
                          ),
                        ),
                        ...wifiOnly.map(
                          (peer) => _NearbyCard(
                            icon: Icons.phone_android_rounded,
                            title: peer.name.isEmpty
                                ? 'Nearby LocalLink phone'
                                : peer.name,
                            subtitle: 'Not paired yet',
                            action: FilledButton.tonal(
                              onPressed: state.busy
                                  ? null
                                  : () => _pairWithWifiPeer(peer),
                              child: state.busy
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : const Text('Pair'),
                            ),
                          ),
                        ),
                        ...live.map(
                          (peer) => _NearbyCard(
                            icon: Icons.check_circle_outline_rounded,
                            title:
                                'Connected ·…${peer.nodeId.length > 8 ? peer.nodeId.substring(peer.nodeId.length - 8) : peer.nodeId}',
                            subtitle:
                                '${peer.state.toLowerCase()} — ${_nearbyTransportLabel(peer.transport)} · ${_nearbyWhen(peer.lastSeenAt)}',
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    ),
    );
  }
}

String _nearbyWhen(int? lastSeenAt) {
  if (lastSeenAt == null || lastSeenAt <= 0) return 'seen just now';
  final age = DateTime.now().millisecondsSinceEpoch - lastSeenAt;
  if (age < 0) return 'seen just now';
  if (age < 60000) return 'seen ${(age / 1000).round()}s ago';
  return 'seen ${(age / 60000).round()}m ago';
}

String _nearbyTransportLabel(String transport) => switch (transport) {
      'lan' => 'same Wi-Fi / LAN',
      'wifi_direct' => 'Wi-Fi Direct',
      _ => 'local network',
    };

/// Bundle 118: single compact card per nearby phone — one title, one short
/// subtitle, at most one action. Replaces the old two-section layout
/// (Wi-Fi Direct "Connect" card + mesh "Pair" card).
class _NearbyCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;
  const _NearbyCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Icon(icon, size: 20)),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: action,
      ),
    );
  }
}
