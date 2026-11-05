// Bundle 223 (Phase 6, F): Wi-Fi Direct name tags on the Dart side.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/connectivity/data/models/nearby_tag.dart';
import 'package:locallink/features/directory/presentation/nearby_list_plan.dart';

void main() {
  const full = '1a2b3c4d5e6f7a8b';
  final nameMap = <String, Object>{
    'address': 'AA:BB:CC:DD:EE:01',
    'id': '1a2b3c4d',
    'host': true,
    'member': false,
    'members': 0,
    'full': false,
    'seen_at': 7,
    'gv': true,
    'from_name': true,
    'wants_link': true,
  };

  setUp(() => NearbyTagRegistry.instance.resetForTest());

  test('223-16b a name tag is read with from_name, no group, no key', () {
    final t = NearbyTag.fromMap(nameMap)!;
    expect(t.fromName, isTrue);
    expect(t.wantsLink, isTrue);
    expect(t.idHash, '1a2b3c4d');
    expect(t.address, 'aa:bb:cc:dd:ee:01');
    expect(t.host, isTrue);
    expect(t.group, isNull);
    expect(t.key, isNull);
    // A full TXT tag is unchanged.
    final f = NearbyTag.fromMap({'address': 'aa:bb', 'id': full})!;
    expect(f.fromName, isFalse);
    expect(f.wantsLink, isFalse);
  });

  test('223-16b the registry notices a full tag replacing a name tag', () {
    var changes = 0;
    void listener() => changes++;
    NearbyTagRegistry.instance.addListener(listener);
    addTearDown(() => NearbyTagRegistry.instance.removeListener(listener));
    NearbyTagRegistry.instance.ingest([NearbyTag.fromMap(nameMap)!]);
    expect(changes, 1);
    NearbyTagRegistry.instance.ingest([
      NearbyTag(address: 'aa:bb:cc:dd:ee:01', idHash: '1a2b3c4d', host: true, fromName: false),
    ]);
    expect(changes, 2);
  });

  test('223-16c Q14 Pair finds the LAN phone from an 8-char name id', () {
    String hashOf(String id) => id == 'node-zte' ? full : 'ffffffffffffffff';
    expect(
        pickPairTarget(
            unpairedBefore: const {},
            unpairedNow: const ['node-other', 'node-zte'],
            wantedTagId: '1a2b3c4d',
            hashOf: hashOf),
        'node-zte');
    // A full id still has to match exactly.
    expect(
        pickPairTarget(
            unpairedBefore: const {},
            unpairedNow: const ['node-zte'],
            wantedTagId: '1a2b3c4d5e6f7a8c',
            hashOf: hashOf),
        isNull);
    expect(tagIdMatches(full, '1a2b3c4d'), isTrue);
    expect(tagIdMatches(full, '1a2b3c'), isFalse);
    expect(tagIdMatches(full, full), isTrue);
  });

  test('223-16d Q15 a friend\'s or blocked person\'s name tag is not shown as new', () {
    String hashOf(String id) => switch (id) {
          'friend' => full,
          'blocked' => '9999aaaa00001111',
          _ => '0000000000000000',
        };
    final friendPlan = planNearbyList(
      discoveredNodeIds: const [],
      liveNodeIds: const [],
      trustedIds: const {'friend'},
      blockedIds: const {'blocked'},
      liveMeansContact: false,
      wifiAddresses: const ['aa:01', 'aa:02', 'aa:03'],
      tagIdByAddress: const {'aa:01': '1a2b3c4d', 'aa:02': '9999aaaa', 'aa:03': '12341234'},
      hashOf: hashOf,
    );
    expect(friendPlan.wifiAddresses, ['aa:03'], reason: 'only the stranger shows');
    expect(friendPlan.emptyState, NearbyEmptyState.none);
    expect(fullTagId('1a2b3c4d', [full, 'x']), full);
    expect(fullTagId('1a2b3c4d', [full, '1a2b3c4d00000000']), '1a2b3c4d', reason: 'two matches: unsure');
    expect(fullTagId(full, [full]), full);
  });

  test('223-16e Q13 source: name tags stay out of the group rules and pairTap', () {
    final s = File('lib/features/connectivity/data/services/wifi_direct_fallback_service.dart')
        .readAsStringSync();
    expect(s, contains('final tags = [for (final t in all) if (!t.fromName) t];'));
    expect(s, contains('NearbyTagRegistry.instance.ingest(all);'));
    expect(s, contains('final tag = _tags[address] ?? (known != null && !known.fromName ? known : null);'));
  });
}
