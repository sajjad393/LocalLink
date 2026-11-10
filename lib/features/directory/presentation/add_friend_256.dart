import 'package:flutter/material.dart';

import 'package:locallink/core/services/app_logger.dart';

/// Bundle 256 E1/E2: plain words for an Add that failed (and a log line).
String friendAddFailText256(Object error) {
  final t = error.toString().toLowerCase();
  if (t.contains('no active device')) {
    return "Their phone is not known yet. Ask them to open LinkUp near you, then try again.";
  }
  if (t.contains('not found or unavailable')) {
    return 'This person could not be found now. Try again near them or scan their QR code.';
  }
  if (t.contains('blocked')) return 'You blocked this person. Unblock them first.';
  if (t.contains('invalid contact')) return "You can't add yourself.";
  return 'Could not add this person. Try again.';
}

void logFriendAddFail256(String source, Object error) {
  var reason = error.toString().split('\n').first.trim();
  if (reason.length > 60) reason = reason.substring(0, 60);
  AppLogger.warning('FRIEND_ADD_FAIL', detail: 'source=$source reason=$reason');
}

/// Bundle 256 E3: the one-line status at the top of Add Contact.
enum AddStatus256 { server, noServer, wifiOff }

AddStatus256 addStatus256({required bool serverConnected, required bool? wifi}) {
  if (serverConnected) return AddStatus256.server;
  if (wifi == false) return AddStatus256.wifiOff;
  return AddStatus256.noServer;
}

String addStatusText256(AddStatus256 s) => switch (s) {
      AddStatus256.server => 'Server connected',
      AddStatus256.noServer => 'No server - searching nearby phones',
      AddStatus256.wifiOff => 'Wi-Fi off - using Wi-Fi Direct',
    };

class AddStatusLine256 extends StatelessWidget {
  final AddStatus256 status;
  final bool busy;
  final VoidCallback? onTap;
  const AddStatusLine256({super.key, required this.status, this.busy = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ok = status == AddStatus256.server;
    final color = ok ? const Color(0xFF15803D) : scheme.onSurfaceVariant;
    return InkWell(
      key: const ValueKey('add_status_256'),
      borderRadius: BorderRadius.circular(12),
      onTap: ok || busy ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(children: [
          Icon(
              ok
                  ? Icons.cloud_done_outlined
                  : status == AddStatus256.wifiOff
                      ? Icons.wifi_off_rounded
                      : Icons.cloud_off_outlined,
              size: 16,
              color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(addStatusText256(status),
                style: TextStyle(fontSize: 12.5, color: color, fontWeight: FontWeight.w500)),
          ),
          if (busy)
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
          else if (!ok)
            Text('Find server now',
                style: TextStyle(fontSize: 12.5, color: scheme.primary, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}
