import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/core/widgets/local_link_state_view.dart';
import 'package:locallink/features/connectivity/bloc/connectivity_bloc.dart';

class NearbyDevicesScreen extends StatefulWidget {
  final ConnectivityBloc connectivity;
  const NearbyDevicesScreen({super.key, required this.connectivity});

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

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConnectivityBloc, ConnectivityState>(
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
                const SizedBox(
                  height: 220,
                  child: LocalLinkEmptyView(
                    icon: Icons.radar_rounded,
                    title: 'No nearby phones found',
                    message: 'Make sure the other phone is nearby and Wi-Fi Direct is available.',
                  ),
                )
              else
                ...peers.map(
                  (peer) => Card(
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.phone_android)),
                      title: Text(peer.name.isEmpty ? 'Nearby LocalLink phone' : peer.name),
                      subtitle: const Text('Nearby connection available'),
                      trailing: FilledButton.tonal(
                        onPressed: () => widget.connectivity.connectWifiDirect(peer),
                        child: const Text('Connect'),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
