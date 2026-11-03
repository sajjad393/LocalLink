import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:locallink/features/connectivity/data/models/wifi_direct_models.dart';
import 'package:locallink/features/connectivity/data/services/nearby_group_planner.dart';

/// Bundle 200 (B): the backup Wi-Fi Direct group for one friend pair.
///
/// The tag search (DNS-SD) often hears nothing, so friends never found each
/// other without a router. Both friends already share a secret link key
/// (Bundle 160, X25519 + HKDF). From it both phones work out the SAME group
/// name and password — nobody else can. One phone hosts that group, the
/// other joins it silently (like a saved Wi-Fi network, no pop-up).
///
/// Finding the group needs no location permission: the Wi-Fi Direct peer
/// list already says which nearby phone hosts a group (`go`). A host phone
/// without a LinkUp tag is tried with the pair's password; a wrong guess just
/// fails after 25 s and that phone is skipped for a while.
class FriendLinkCredentials {
  /// `DIRECT-LL-` + 6 letters (the same style as the normal shared groups).
  final String name;

  /// 16 letters / digits.
  final String pass;

  const FriendLinkCredentials(this.name, this.pass);

  static const String namePrefix = 'DIRECT-LL-';
  static const String _alphabet =
      'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';
  static final RegExp _hex = RegExp(r'^[0-9a-f]{64}$');

  /// Null when [keyHex] is not a 32-byte hex link key.
  static FriendLinkCredentials? fromKeyHex(String? keyHex) {
    final clean = keyHex?.trim().toLowerCase() ?? '';
    if (!_hex.hasMatch(clean)) return null;
    final key = <int>[
      for (var i = 0; i < clean.length; i += 2)
        int.parse(clean.substring(i, i + 2), radix: 16),
    ];
    final mac = Hmac(sha256, key);
    final nameBytes = mac.convert(utf8.encode('wd-name-v1')).bytes;
    final passBytes = mac.convert(utf8.encode('wd-pass-v1')).bytes;
    return FriendLinkCredentials(
      '$namePrefix${_text(nameBytes, 6)}',
      _text(passBytes, 16),
    );
  }

  static String _text(List<int> bytes, int length) {
    final out = StringBuffer();
    for (var i = 0; i < length; i++) {
      out.write(_alphabet[bytes[i] % _alphabet.length]);
    }
    return out.toString();
  }

  /// For logs: the group name without the password, shortened.
  String get shortName => name.length > 13 ? '${name.substring(0, 13)}…' : name;
}

/// One friend the backup link may be made for.
class FriendLinkFriend {
  final String id;

  /// [NearbyTag.idFor] of the friend's device id (decides who opens).
  final String hash;
  final FriendLinkCredentials creds;

  /// Reachable over Local Wi-Fi / mesh / an existing group right now.
  final bool reachable;

  /// A fresh LinkUp tag of this friend was heard (the normal rules handle it).
  final bool tagSeen;

  /// When this friend became unreachable without a tag (0 = not wanted).
  final int wantedSince;

  /// A message (or a call) waits for this friend.
  final bool pending;

  const FriendLinkFriend({
    required this.id,
    required this.hash,
    required this.creds,
    this.reachable = false,
    this.tagSeen = false,
    this.wantedSince = 0,
    this.pending = false,
  });
}

enum FriendLinkKind { none, open, join, leaveAndJoin, close }

class FriendLinkAction {
  final FriendLinkKind kind;
  final FriendLinkFriend? friend;

  /// Wi-Fi Direct address of the host phone to join (join / leaveAndJoin).
  final String? address;
  final String reason;

  const FriendLinkAction._(this.kind, this.friend, this.address, this.reason);
  const FriendLinkAction.none(String reason)
      : this._(FriendLinkKind.none, null, null, reason);
  const FriendLinkAction.open(FriendLinkFriend friend, String reason)
      : this._(FriendLinkKind.open, friend, null, reason);
  const FriendLinkAction.join(
      FriendLinkFriend friend, String address, String reason)
      : this._(FriendLinkKind.join, friend, address, reason);
  const FriendLinkAction.leaveAndJoin(
      FriendLinkFriend friend, String address, String reason)
      : this._(FriendLinkKind.leaveAndJoin, friend, address, reason);
  const FriendLinkAction.close(String reason)
      : this._(FriendLinkKind.close, null, null, reason);

  bool get acts => kind != FriendLinkKind.none;
}

/// Bundle 200 (B) rule constants.
abstract final class FriendLinkRules {
  /// One full tag search window found no tag of the friend.
  static const int signWaitMs = 20 * 1000;

  /// The bigger id opens only when something waits and no friend group
  /// appeared this much longer (Q1 a).
  static const int biggerWaitMs = 30 * 1000;

  /// A friend group nobody joined closes after this long.
  static const int idleCloseMs = 3 * 60 * 1000;

  /// After an idle close: rest before opening again (10 min after 3 in a
  /// row, battery).
  static const int openRestMs = 2 * 60 * 1000;
  static const int openLongRestMs = 10 * 60 * 1000;
  static const int longRestAfterCloses = 3;

  /// A failed join on one host phone: skip it this long (30 min after 2).
  static const int skipMs = 5 * 60 * 1000;
  static const int longSkipMs = 30 * 60 * 1000;

  /// At most this many friends at once (Q4 b; more in TODO_201).
  static const int maxFriends = 2;
}

class FriendLinkInput {
  final int now;
  final String selfHash;
  final NearbyGroupRole role;
  final String? myGroup;
  final int myMembers;
  final int hostSince;

  /// On a normal Wi-Fi network that really connects phones.
  final bool onWifi;

  /// A call goes on (a group is never closed or changed under it).
  final bool busy;

  /// Battery rules allow searching / opening (not ≤10% with the app closed).
  final bool allowed;
  final List<FriendLinkFriend> friends;
  final List<WifiDirectPeer> peers;

  /// Wi-Fi Direct addresses with a fresh LinkUp tag (normal rules).
  final Set<String> taggedAddresses;

  /// `address|friendHash` pairs that failed lately.
  final Set<String> skip;

  /// No new open before this time (rest after idle closes).
  final int openRestUntil;

  const FriendLinkInput({
    required this.now,
    required this.selfHash,
    required this.role,
    this.myGroup,
    this.myMembers = 0,
    this.hostSince = 0,
    this.onWifi = false,
    this.busy = false,
    this.allowed = true,
    this.friends = const <FriendLinkFriend>[],
    this.peers = const <WifiDirectPeer>[],
    this.taggedAddresses = const <String>{},
    this.skip = const <String>{},
    this.openRestUntil = 0,
  });
}

/// The friend whose backup group [group] is (or null).
FriendLinkFriend? friendOfGroup(List<FriendLinkFriend> friends, String? group) {
  if (group == null) return null;
  for (final f in friends) {
    if (f.creds.name == group) return f;
  }
  return null;
}

String friendSkipKey(String address, String friendHash) =>
    '${address.trim().toLowerCase()}|$friendHash';

/// Bundle 200 (B): what to do for the friend backup link. Runs only when the
/// normal tag rules did nothing.
///
/// * smaller id opens the pair's group when a phone without a tag is seen
///   nearby; the bigger id opens only with something waiting, 30 s later;
/// * the bigger id joins a host phone without a tag using the pair password;
/// * both hosting: the bigger id leaves and joins;
/// * a linked friend group stays (Q2), never closed during a call;
/// * an empty friend group closes after 3 min (then a rest).
FriendLinkAction planFriendLink(FriendLinkInput input) {
  final mine = friendOfGroup(input.friends, input.myGroup);

  List<String> untaggedHosts(FriendLinkFriend f) => [
        for (final p in input.peers)
          if (p.groupOwner &&
              p.address.isNotEmpty &&
              !input.taggedAddresses.contains(p.address.toLowerCase()) &&
              !input.skip.contains(friendSkipKey(p.address, f.hash)))
            p.address.toLowerCase(),
      ];

  if (input.onWifi) {
    if (input.role == NearbyGroupRole.host &&
        mine != null &&
        input.myMembers == 0 &&
        !input.busy) {
      return const FriendLinkAction.close('router_back');
    }
    return const FriendLinkAction.none('on_router');
  }

  switch (input.role) {
    case NearbyGroupRole.member:
      return const FriendLinkAction.none('member_keeps_group');
    case NearbyGroupRole.host:
      if (mine == null) return const FriendLinkAction.none('host_keeps_group');
      if (input.myMembers > 0) return const FriendLinkAction.none('linked');
      if (input.busy) return const FriendLinkAction.none('busy');
      // Both phones host the pair's group: the bigger id moves.
      if (input.selfHash.compareTo(mine.hash) > 0) {
        final hosts = untaggedHosts(mine);
        if (hosts.isNotEmpty) {
          return FriendLinkAction.leaveAndJoin(mine, hosts.first, 'both_host');
        }
      }
      if (input.hostSince > 0 &&
          input.now - input.hostSince >= FriendLinkRules.idleCloseMs) {
        return const FriendLinkAction.close('idle');
      }
      return const FriendLinkAction.none('host_waits');
    case NearbyGroupRole.none:
      break;
  }

  if (!input.allowed) return const FriendLinkAction.none('battery');
  final wanted = [
    for (final f in input.friends)
      if (!f.reachable &&
          !f.tagSeen &&
          f.wantedSince > 0 &&
          input.now - f.wantedSince >= FriendLinkRules.signWaitMs)
        f,
  ]..sort((a, b) {
      if (a.pending != b.pending) return a.pending ? -1 : 1;
      final since = a.wantedSince.compareTo(b.wantedSince);
      if (since != 0) return since;
      return a.hash.compareTo(b.hash);
    });
  if (wanted.isEmpty) return const FriendLinkAction.none('no_friend');
  final top = wanted.take(FriendLinkRules.maxFriends).toList();

  // 1. Join: a host phone without a tag, for a friend with a smaller id
  // (that friend opens the group).
  for (final f in top) {
    if (input.selfHash.compareTo(f.hash) <= 0) continue;
    final hosts = untaggedHosts(f);
    if (hosts.isNotEmpty) {
      return FriendLinkAction.join(f, hosts.first, 'friend_group_seen');
    }
  }

  // 2. Open: only when some phone without a tag is nearby (it may be the
  // friend) - no group for nobody (battery).
  if (input.now < input.openRestUntil) {
    return const FriendLinkAction.none('open_rest');
  }
  final phoneSeen = input.peers.any((p) =>
      p.isAvailable &&
      !p.groupOwner &&
      p.address.isNotEmpty &&
      !input.taggedAddresses.contains(p.address.toLowerCase()));
  if (!phoneSeen) return const FriendLinkAction.none('no_phone_seen');
  for (final f in top) {
    if (input.selfHash.compareTo(f.hash) < 0) {
      return FriendLinkAction.open(f, 'smaller_opens');
    }
  }
  for (final f in top) {
    if (f.pending &&
        input.now - f.wantedSince >=
            FriendLinkRules.signWaitMs + FriendLinkRules.biggerWaitMs) {
      return FriendLinkAction.open(f, 'bigger_opens_waiting');
    }
  }
  return const FriendLinkAction.none('wait_friend_group');
}
