import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

/// Bundle 298 (D): the small map cards (Chats "My links", admin card) are
/// wide strips. The 212 spots put every Wi-Fi Direct person to the LEFT of
/// "You" (mesh up-right, local Wi-Fi down-right), so with only Wi-Fi Direct
/// friends the right half stayed empty.
///
/// Small cards only (the big map keeps the 212 spots): people are split
/// between both sides of "You" and spread over the card width. Pure maths,
/// same input = same map.
///
/// - A group of people joined by a line (a mesh chain) moves together, so
///   no line gets long or crosses the card.
/// - People reached through the server stay round the cloud (left).
/// - Offline people (upper arc) stay where they are.
/// - Moving = mirror round "You" (same distance from You, same height).
/// - Then each side is stretched (x only, at most [maxStretch]) so the
///   people use the room up to the card edge (name room kept).
class LinkBalance298 {
  LinkBalance298._();

  static const double maxStretch = 1.6;

  /// Half the small name line: x stays inside [edge, width - edge].
  static const double edge = 38;

  /// [place] = the 212 spots; [movable] = ids that may change side (live,
  /// not server-linked); [links] = lines between two people (id pairs).
  static Map<String, Offset> balance(
    Map<String, Offset> place,
    Size size, {
    required Offset self,
    required Set<String> movable,
    List<(String, String)> links = const [],
  }) {
    if (place.isEmpty || size.width <= 0) return place;
    final out = Map<String, Offset>.of(place);
    final ids = [
      for (final id in place.keys)
        if (movable.contains(id)) id
    ]..sort();
    if (ids.isEmpty) return out;

    // Groups joined by a line move together (union-find, sorted ids).
    final parent = {for (final id in ids) id: id};
    String find(String x) {
      var r = x;
      while (parent[r] != r) {
        r = parent[r]!;
      }
      return r;
    }

    for (final (a, b) in links) {
      if (!parent.containsKey(a) || !parent.containsKey(b)) continue;
      final ra = find(a), rb = find(b);
      if (ra == rb) continue;
      if (ra.compareTo(rb) < 0) {
        parent[rb] = ra;
      } else {
        parent[ra] = rb;
      }
    }
    final groups = <String, List<String>>{};
    for (final id in ids) {
      groups.putIfAbsent(find(id), () => []).add(id);
    }

    bool leftOf(String id) => out[id]!.dx < self.dx;
    // Everyone counts (server-linked and offline people too), only the
    // movable groups move.
    int count(bool left) => out.keys.where((id) => leftOf(id) == left).length;

    // Best when left - right is 0 or -1: the cloud is on the left, so an
    // odd one out goes right.
    int miss(int d) => math.max(d, -d - 1);
    final keys = groups.keys.toList()..sort();
    for (var guard = 0; guard < keys.length; guard++) {
      final l = count(true), r = count(false);
      if (miss(l - r) == 0) break;
      final fromLeft = l > r;
      String? best;
      var bestGap = miss(l - r);
      for (final k in keys) {
        final g = groups[k]!;
        if (g.any((id) => leftOf(id) != fromLeft)) continue; // split group: leave it
        final n = g.length;
        final gap = miss(fromLeft ? (l - r - 2 * n) : (l - r + 2 * n));
        if (gap < bestGap) {
          bestGap = gap;
          best = k;
        }
      }
      if (best == null) break;
      for (final id in groups[best]!) {
        final p = out[id]!;
        out[id] = Offset((2 * self.dx - p.dx).clamp(edge, math.max(edge, size.width - edge)), p.dy);
      }
    }

    // Stretch each side so the people use the card width.
    for (final left in [true, false]) {
      final side = [
        for (final id in ids)
          if (leftOf(id) == left) id
      ];
      if (side.isEmpty) continue;
      var far = 0.0;
      for (final id in side) {
        far = math.max(far, (out[id]!.dx - self.dx).abs());
      }
      if (far < 1) continue;
      final room = left ? self.dx - edge : size.width - edge - self.dx;
      final k = (room / far).clamp(1.0, maxStretch).toDouble();
      for (final id in side) {
        final p = out[id]!;
        out[id] = Offset(self.dx + (p.dx - self.dx) * k, p.dy);
      }
    }
    return out;
  }
}
