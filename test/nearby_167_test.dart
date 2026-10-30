import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/connectivity/data/models/nearby_tag.dart';
import 'package:locallink/features/connectivity/data/services/nearby_group_planner.dart';
import 'package:locallink/features/connectivity/data/services/voice_relay_watch.dart';

// Bundle 167 (5.5): a voice call survives a host change.

const _now = 1000000000;

NearbyTag _mate(String deviceId, int i, {bool inCall = false, bool charging = false}) =>
    NearbyTag(
      address: 'aa:bb:cc:dd:ee:1$i',
      idHash: NearbyTag.idFor(deviceId),
      groupAware: true,
      inCall: inCall,
      charging: charging,
      seenAt: _now,
    );

NearbyGroupAction _lost({
  required String self,
  required List<NearbyTag> mates,
  required int sinceLost,
  bool busy = false,
  bool selfCharging = false,
  List<NearbyTag> extra = const [],
}) =>
    planNearbyGroup(NearbyGroupInput(
      selfHash: NearbyTag.idFor(self),
      now: _now,
      tags: [...mates, ...extra],
      lostAt: _now - sinceLost,
      lostJitterMs: 3000,
      lostMates: {for (final m in mates) m.idHash},
      busy: busy,
      selfCharging: selfCharging,
    ));

/// A device id whose hash is bigger than all of [others] (never first by id).
String _biggest(List<String> others) {
  for (var i = 0;; i++) {
    final id = 'z$i';
    final h = NearbyTag.idFor(id);
    if (others.every((o) => h.compareTo(NearbyTag.idFor(o)) > 0)) return id;
  }
}

void main() {
  test('a phone in a call goes before chargers and smaller ids', () {
    expect(nearbyGoesFirst('ff', false, '00', true, aCall: true), isTrue);
    expect(nearbyGoesFirst('00', true, 'ff', false, bCall: true), isFalse);
    // Both or neither in a call: the 159 rule as before.
    expect(nearbyGoesFirst('00', false, 'ff', false), isTrue);
    expect(nearbyGoesFirst('ff', true, '00', false, aCall: true, bCall: true), isTrue);
  });

  test('host left: the phone in a call creates the new group at once', () {
    final mates = [_mate('m1', 1), _mate('m2', 2)];
    final me = _biggest(['m1', 'm2']);
    // Not in a call: waits the random 1-4 s, and isn't first by id.
    expect(_lost(self: me, mates: mates, sinceLost: 500).reason, 'host_left_wait');
    expect(_lost(self: me, mates: mates, sinceLost: 3500).reason, 'host_left_wait_new_host');
    // In a call: after 0.3 s it becomes the new host.
    final p = _lost(self: me, mates: mates, sinceLost: 400, busy: true);
    expect(p.kind, NearbyGroupActionKind.create);
    expect(p.reason, 'host_left_new_host');
  });

  test('the other phones let the phone in a call go first', () {
    const me = 'a0';
    final callPhone = _biggest([me]);
    final p = _lost(
        self: me,
        mates: [_mate(callPhone, 1, inCall: true)],
        sinceLost: 3500,
        selfCharging: true);
    expect(p.kind, NearbyGroupActionKind.none);
    expect(p.reason, 'host_left_wait_new_host');
  });

  test('the call partner joins the new group as soon as it is seen', () {
    final partner = _mate('p1', 1, inCall: true);
    final newHost = NearbyTag(
      address: 'aa:bb:cc:dd:ee:99',
      idHash: NearbyTag.idFor('p1'),
      host: true,
      groupAware: true,
      group: 'DIRECT-LL-p1',
      key: 'pass-p1-1234',
      inCall: true,
      seenAt: _now,
    );
    final p = _lost(
        self: _biggest(['p1']),
        mates: [partner],
        extra: [newHost],
        sinceLost: 400,
        busy: true);
    expect(p.kind, NearbyGroupActionKind.join);
  });

  test('two phones in the same call: only one creates', () {
    const a = 'c1';
    const b = 'c2';
    final pa = _lost(self: a, mates: [_mate(b, 1, inCall: true)], sinceLost: 400, busy: true);
    final pb = _lost(self: b, mates: [_mate(a, 1, inCall: true)], sinceLost: 400, busy: true);
    final creators = [pa, pb].where((p) => p.kind == NearbyGroupActionKind.create).length;
    expect(creators, 1);
  });

  test('a host carrying a call does not merge into a bigger group', () {
    final bigger = NearbyTag(
      address: 'aa:bb:cc:dd:ee:50',
      idHash: NearbyTag.idFor('big'),
      host: true,
      members: 5,
      groupAware: true,
      group: 'DIRECT-LL-big',
      key: 'pass-big-1234',
      seenAt: _now,
    );
    NearbyGroupAction plan(bool busy) => planNearbyGroup(NearbyGroupInput(
          selfHash: NearbyTag.idFor('me'),
          now: _now,
          role: NearbyGroupRole.host,
          myGroup: 'DIRECT-LL-me',
          myMembers: 2,
          hostSince: _now - 60000,
          tags: [bigger],
          firstSeen: {bigger.address: _now - 60000},
          busy: busy,
        ));
    expect(plan(false).reason, 'merge_into_bigger');
    expect(plan(true).kind, NearbyGroupActionKind.none);
  });

  test('the call flag is read from the nearby tag', () {
    final t = NearbyTag.fromMap({
      'address': 'aa:bb:cc:dd:ee:ff',
      'id': '0123456789abcdef',
      'in_call': true,
    });
    expect(t?.inCall, isTrue);
    expect(NearbyTag.fromMap({'address': 'aa:bb:cc:dd:ee:ff', 'id': '0123456789abcdef'})?.inCall, isFalse);
  });

  test('voice passing through: on, refreshed, off, and runs out by itself', () {
    final w = VoiceRelayWatch();
    final t = DateTime(2026, 10, 31, 12);
    expect(w.active(t), isFalse);
    w.note(true, t);
    expect(w.active(t.add(const Duration(seconds: 20))), isTrue);
    expect(w.active(t.add(const Duration(seconds: 30))), isFalse, reason: 'lost off event');
    w.note(true, t.add(const Duration(seconds: 10)));
    w.note(false, t.add(const Duration(seconds: 12)));
    expect(w.active(t.add(const Duration(seconds: 13))), isFalse);
  });
}
