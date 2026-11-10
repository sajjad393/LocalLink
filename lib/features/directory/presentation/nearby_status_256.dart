import 'package:flutter/material.dart';

/// Bundle 256 E6: one small chip under "Nearby" (why the list may be empty).
class NearbyChip256 {
  final String id;
  final String label;
  final bool good;
  final IconData icon;
  const NearbyChip256(this.id, this.label, this.good, this.icon);
}

/// Wi-Fi on/off, Wi-Fi Direct on/off, Bluetooth allowed / off / on.
/// [wifi] null = not known yet (chip left out), [ble] = NearbyBleStatus word.
List<NearbyChip256> nearbyChips256({
  required bool? wifi,
  required bool wifiDirectOn,
  required String ble,
}) {
  return [
    if (wifi == true)
      const NearbyChip256('wifi', 'Wi-Fi on', true, Icons.wifi_rounded)
    else if (wifi == false)
      const NearbyChip256('wifi', 'Wi-Fi off', false, Icons.wifi_off_rounded),
    if (wifiDirectOn)
      const NearbyChip256('wd', 'Wi-Fi Direct on', true, Icons.wifi_tethering_rounded)
    else
      const NearbyChip256('wd', 'Wi-Fi Direct off', false, Icons.portable_wifi_off_rounded),
    if (ble == 'no_permission')
      const NearbyChip256('ble', 'Bluetooth not allowed', false, Icons.bluetooth_disabled_rounded)
    else if (ble == 'off')
      const NearbyChip256('ble', 'Bluetooth off', false, Icons.bluetooth_disabled_rounded)
    else if (ble == 'on' || ble == 'scan_only')
      const NearbyChip256('ble', 'Bluetooth on', true, Icons.bluetooth_rounded),
  ];
}

/// Bundle 256 E8: "Seen 40 s ago" / "Seen 1 min ago".
String nearbySeenLabel256(int ageMs) {
  final s = (ageMs / 1000).floor().clamp(0, 3600);
  if (s < 60) return 'Seen ${s < 5 ? 5 : (s ~/ 5) * 5} s ago';
  return 'Seen ${s ~/ 60} min ago';
}

/// Bundle 256 E8: a phone that just left the list stays 2 min (greyed,
/// Add friend still works). Pure memory, this screen only.
class NearbyKept256<T> {
  static const int keepMs = 120000;

  final Map<String, ({String? name, T peer, int lastMs})> _seen = {};

  /// The list shown now: remember each one with [nowMs].
  void saw(Iterable<({String id, String? name, T peer})> shown, int nowMs) {
    for (final e in shown) {
      final old = _seen[e.id];
      _seen[e.id] = (name: e.name ?? old?.name, peer: e.peer, lastMs: nowMs);
    }
  }

  /// Phones seen within 2 min that are NOT shown now (newest first).
  /// [skip] = shown now, friends, blocked, own phones.
  List<({String id, String? name, T peer, int ageMs})> kept(int nowMs, Set<String> skip) {
    _seen.removeWhere((_, v) => nowMs - v.lastMs >= keepMs);
    final out = [
      for (final e in _seen.entries)
        if (!skip.contains(e.key))
          (id: e.key, name: e.value.name, peer: e.value.peer, ageMs: nowMs - e.value.lastMs),
    ]..sort((a, b) => a.ageMs.compareTo(b.ageMs));
    return out;
  }

  void forget(String id) => _seen.remove(id);
  bool get isEmpty => _seen.isEmpty;
}

/// Bundle 256 E9 + log: why the list is empty, in one word.
String nearbyWhyEmpty256({required int shown, required bool? wifi, required String ble}) {
  if (shown > 0) return '-';
  if (wifi == false) return 'wifi_off';
  if (ble == 'no_permission') return 'no_perm';
  return 'none';
}

/// Bundle 256: the `NEARBY_LIST` line (every 30 s while Add Contact is open).
String nearbyListLog256({
  required int shown,
  required int lan,
  required int wd,
  required int ble,
  required int kept,
  required bool? wifi,
  required String bleState,
}) =>
    'shown=$shown lan=$lan wd=$wd ble=$ble kept=$kept '
    'why_empty=${nearbyWhyEmpty256(shown: shown, wifi: wifi, ble: bleState)}';

/// Bundle 256 E6: the chips row (built like small Material chips).
class NearbyChips256 extends StatelessWidget {
  final List<NearbyChip256> chips;
  const NearbyChips256({super.key, required this.chips});

  @override
  Widget build(BuildContext context) {
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          for (final c in chips)
            DecoratedBox(
              key: ValueKey<String>('nearby_chip_${c.id}'),
              decoration: BoxDecoration(
                color: c.good ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(c.icon,
                      size: 14, color: c.good ? const Color(0xFF15803D) : const Color(0xFFB91C1C)),
                  const SizedBox(width: 4),
                  Text(c.label,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: c.good ? const Color(0xFF15803D) : const Color(0xFFB91C1C))),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}
