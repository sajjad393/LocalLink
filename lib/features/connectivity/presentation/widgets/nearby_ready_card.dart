import 'dart:async';

import 'package:flutter/material.dart';
import 'package:locallink/features/connectivity/data/services/wifi_direct_service.dart';
import 'package:locallink/features/connectivity/data/services/wifi_radio_control_service.dart';

/// Bundle 159.1: what the "ready for nearby" card should say.
enum NearbyReadyCardKind { none, allowNearby, turnOnWifi }

/// One card at a time: the Nearby devices permission first (Location on
/// Android 12 and older — the native side asks the right one), then Wi-Fi.
/// Unknown (null) never shows a card.
NearbyReadyCardKind nearbyReadyCardKind({
  required bool? nearbyAllowed,
  required bool? wifiOn,
}) {
  if (nearbyAllowed == false) return NearbyReadyCardKind.allowNearby;
  if (wifiOn == false) return NearbyReadyCardKind.turnOnWifi;
  return NearbyReadyCardKind.none;
}

/// Reads and fixes the two things nearby chat needs.
abstract interface class NearbyReadinessProbe {
  Future<bool?> nearbyAllowed();
  Future<bool?> wifiOn();
  Future<void> askNearby();
  Future<void> openWifi();
}

final class PlatformNearbyReadinessProbe implements NearbyReadinessProbe {
  const PlatformNearbyReadinessProbe();

  @override
  Future<bool?> nearbyAllowed() async {
    try {
      return await WifiDirectService().hasPermission();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool?> wifiOn() async {
    try {
      final status = await WifiRadioControlService().status();
      return status.supported ? status.enabled : null;
    } catch (_) {
      return null;
    }
  }

  /// The one native system dialog (no extra pop-up of our own).
  @override
  Future<void> askNearby() async {
    try {
      await WifiDirectService().requestEnable();
    } catch (_) {}
  }

  @override
  Future<void> openWifi() async {
    try {
      await WifiRadioControlService().openSettings();
    } catch (_) {}
  }
}

/// Bundle 159.1: a small card on the Chats list, shown only when nearby
/// chat can't work: "Allow nearby devices" or "Turn on Wi-Fi". It checks
/// again when the app comes back to the front. The x hides it until the
/// app is opened again.
class NearbyReadyCard extends StatefulWidget {
  const NearbyReadyCard({
    super.key,
    this.probe = const PlatformNearbyReadinessProbe(),
  });

  final NearbyReadinessProbe probe;

  @override
  State<NearbyReadyCard> createState() => _NearbyReadyCardState();
}

class _NearbyReadyCardState extends State<NearbyReadyCard>
    with WidgetsBindingObserver {
  static bool _hiddenThisSession = false;

  NearbyReadyCardKind _kind = NearbyReadyCardKind.none;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_check());
  }

  Future<void> _check() async {
    if (_hiddenThisSession) return;
    final allowed = await widget.probe.nearbyAllowed();
    final wifi = await widget.probe.wifiOn();
    if (!mounted) return;
    final kind = nearbyReadyCardKind(nearbyAllowed: allowed, wifiOn: wifi);
    if (kind != _kind) setState(() => _kind = kind);
  }

  Future<void> _act() async {
    if (_kind == NearbyReadyCardKind.allowNearby) {
      await widget.probe.askNearby();
    } else {
      await widget.probe.openWifi();
    }
    await _check();
  }

  @override
  Widget build(BuildContext context) {
    if (_hiddenThisSession || _kind == NearbyReadyCardKind.none) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final nearby = _kind == NearbyReadyCardKind.allowNearby;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            children: [
              Icon(nearby ? Icons.wifi_tethering : Icons.wifi_off,
                  size: 18, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  nearby
                      ? 'Allow nearby devices to reach people without internet.'
                      : 'Turn on Wi-Fi to reach people nearby.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              TextButton(
                onPressed: _act,
                child: Text(nearby ? 'Allow' : 'Turn on'),
              ),
              IconButton(
                tooltip: 'Hide',
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  _hiddenThisSession = true;
                  setState(() {});
                },
                icon: Icon(Icons.close,
                    size: 16, color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
