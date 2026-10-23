import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/directory/data/contact_edge.dart';

ContactEdge edge({
  String op = ContactEdge.opAdd,
  String fromUser = 'u-a',
  String fromDevice = 'd-a',
  String toUser = 'u-b',
  int ts = 1700000000000,
}) =>
    ContactEdge(
      op: op,
      fromUserId: fromUser,
      fromDeviceId: fromDevice,
      toUserId: toUser,
      edgeTs: ts,
    );

void main() {
  group('ContactEdge wire shape', () {
    test('canonical is byte-identical for identical edges (signable both ends)', () {
      expect(edge().canonical(), edge().canonical());
      expect(
        edge().canonical(),
        'contact-edge|v1|add|u-a|d-a|u-b|1700000000000',
      );
    });

    test('round-trips through the gossip map', () {
      final parsed = ContactEdge.fromWire(edge().toMap());
      expect(parsed, isNotNull);
      expect(parsed!.canonical(), edge().canonical());
    });

    test('rejects malformed ops, self-edges and missing fields', () {
      expect(ContactEdge.fromWire(edge(op: 'poke').toMap()), isNull);
      expect(ContactEdge.fromWire(edge(fromUser: 'u-b', toUser: 'u-b').toMap()), isNull);
      expect(ContactEdge.fromWire(edge(ts: 0).toMap()), isNull);
      expect(ContactEdge.fromWire(edge(fromUser: '').toMap()), isNull);
    });
  });

  group('ContactEdge.decideApply — last-writer-wins against replays', () {
    test('unknown local edge: adopt whatever arrives', () {
      expect(ContactEdge.decideApply(edge(), null), 'add');
      expect(ContactEdge.decideApply(edge(op: 'remove'), null), 'remove');
    });

    test('newer incoming wins over local state', () {
      final local = ContactEdge.encodeEdgeState('add', 1000);
      expect(ContactEdge.decideApply(edge(op: 'remove', ts: 2000), local), 'remove');
      final localR = ContactEdge.encodeEdgeState('remove', 1000);
      expect(ContactEdge.decideApply(edge(op: 'add', ts: 2000), localR), 'add');
    });

    test('older/equal incoming is ignored: stale relays cannot resurrect edges', () {
      final local = ContactEdge.encodeEdgeState('remove', 5000);
      // Typical ghost: an 'add' that was broadcast long before the removal.
      expect(ContactEdge.decideApply(edge(op: 'add', ts: 4000), local), isNull);
      expect(ContactEdge.decideApply(edge(op: 'add', ts: 5000), local), isNull);
    });

    test('edge state codec round-trips and rejects junk', () {
      final raw = ContactEdge.encodeEdgeState('remove', 3456);
      final decoded = ContactEdge.decodeEdgeState(raw);
      expect(decoded!.$1, 'remove');
      expect(decoded.$2, 3456);
      expect(ContactEdge.decodeEdgeState('add'), isNull);
      expect(ContactEdge.decodeEdgeState('poke|10'), isNull);
      expect(ContactEdge.decodeEdgeState('add|0'), isNull);
    });
  });
}
