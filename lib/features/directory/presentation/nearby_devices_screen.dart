import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:locallink/features/connectivity/bloc/connectivity_bloc.dart';

class NearbyDevicesScreen extends StatefulWidget {
  final ConnectivityBloc connectivity;
  const NearbyDevicesScreen({super.key, required this.connectivity});

  @override
  State<NearbyDevicesScreen> createState() => _NearbyDevicesScreenState();
}

class _NearbyDevicesScreenState extends State<NearbyDevicesScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
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
          appBar: AppBar(title: const Text('Nearby Devices')),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              SizedBox(
                height: 280,
                child: Center(
                  child: AnimatedBuilder(
                    animation: controller,
                    builder: (_, __) => Stack(
                      alignment: Alignment.center,
                      children: [
                        for (int i = 0; i < 3; i++)
                          Container(
                            width: 100 + (i * 55) +
                                55 * math.sin(
                                  (controller.value + i / 3) * math.pi * 2,
                                ).abs(),
                            height: 100 + (i * 55) +
                                55 * math.sin(
                                  (controller.value + i / 3) * math.pi * 2,
                                ).abs(),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withOpacity(.12),
                                width: 2,
                              ),
                            ),
                          ),
                        CircleAvatar(
                          radius: 38,
                          child: const Icon(Icons.smartphone),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  peers.isEmpty ? 'Searching for nearby devices…' : 'Nearby devices',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: 12),
              if (peers.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      'Keep Wi‑Fi Direct enabled to discover nearby LocalLink phones.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ...peers.map(
                (peer) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.phone_android),
                    title: Text(peer.name),
                    trailing: const Icon(Icons.chevron_right),
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
