import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

/// Bundle 291 (TODO_291 B-4): on the link maps (admin card, full screen,
/// Chats "My links" card) no person sits on top of another and no line runs
/// under a third person's photo or on top of another line.
///
/// Pure maths (no Flutter widgets), cached: the painter repaints every
/// motion frame, the answer only changes when the people or the size do.
class LinkApart291 {
  LinkApart291._();

  static final Map<String, Map<String, Offset>> _cache = {};

  /// Room one person needs: the photo (radius [r]) + its name pill under it.
  /// An ellipse: wider than high (the name is wider than the photo).
  /// The small cards (104 / 110 px high) use a short name line.
  static double roomX(double r, {bool small = false}) => 2 * r + (small ? 22 : 40);
  static double roomY(double r, {bool small = false}) => 2 * r + (small ? 14 : 26);

  /// [place] moved so every two people are at least one "room" apart (and
  /// apart from the [fixed] spots: me and the server), inside the map
  /// (x 16..w-16, y 16..h-34, like the 212 clamp). Ids in sorted order, so
  /// the same input always gives the same map.
  ///
  /// A crowded card (12 people on a 104 px card) has no room for every name:
  /// then the room shrinks step by step (like the web gap, 64..120 px), never
  /// below the photo + 4 px, so photos still never touch.
  static Map<String, Offset> apart(Map<String, Offset> place, Size size,
      {required double r, List<Offset> fixed = const [], bool small = false}) {
    if (place.isEmpty) return place;
    final fx = roomX(r, small: small), fy = roomY(r, small: small);
    final floor = 2 * r + 4;
    var scale = 1.0;
    while (true) {
      final ax = math.max(floor, fx * scale), ay = math.max(floor, fy * scale);
      final out = _apart(place, size, ax, ay, fixed);
      if (out.$2 || (ax <= floor && ay <= floor)) return out.$1;
      scale *= 0.88;
    }
  }

  /// One try with room [ax] x [ay]; `true` = everybody found a free spot.
  static (Map<String, Offset>, bool) _apart(
      Map<String, Offset> place, Size size, double ax, double ay, List<Offset> fixed) {
    final ids = place.keys.toList()..sort();
    final x = <double>[for (final id in ids) place[id]!.dx];
    final y = <double>[for (final id in ids) place[id]!.dy];
    final minX = 16.0, maxX = math.max(16.0, size.width - 16);
    final minY = 16.0, maxY = math.max(16.0, size.height - 34);
    double clampX(double v) => v.clamp(minX, maxX).toDouble();
    double clampY(double v) => v.clamp(minY, maxY).toDouble();
    // Distance in "rooms": >= 1 = free.
    double room(double dx, double dy) =>
        math.sqrt((dx / ax) * (dx / ax) + (dy / ay) * (dy / ay));

    for (var step = 0; step < 300; step++) {
      var moved = false;
      final k = step < 220 ? 0.6 : 1.0;
      for (var i = 0; i < ids.length; i++) {
        for (var j = i + 1; j < ids.length; j++) {
          var dx = (x[j] - x[i]) / ax, dy = (y[j] - y[i]) / ay;
          var d = math.sqrt(dx * dx + dy * dy);
          if (d >= 0.995) continue;
          if (d < 1e-3) {
            final a = (i + j * 2.399963) % (2 * math.pi);
            dx = math.cos(a);
            dy = math.sin(a);
            d = 1;
          }
          final push = (1 - d) / d * 0.5 * k;
          x[i] -= dx * push * ax;
          y[i] -= dy * push * ay;
          x[j] += dx * push * ax;
          y[j] += dy * push * ay;
          moved = true;
        }
      }
      for (var i = 0; i < ids.length; i++) {
        for (final f in fixed) {
          final d = room(x[i] - f.dx, y[i] - f.dy);
          if (d < 0.995) {
            var ux = (x[i] - f.dx) / ax, uy = (y[i] - f.dy) / ay;
            if (d < 1e-3) {
              ux = 0;
              uy = 1;
            } else {
              ux /= d;
              uy /= d;
            }
            x[i] = f.dx + ux * ax;
            y[i] = f.dy + uy * ay;
            moved = true;
          }
        }
        x[i] = clampX(x[i]);
        y[i] = clampY(y[i]);
      }
      if (!moved) break;
    }

    // Still on top of someone (a crowded small card): the nearest free spot
    // on a half-room grid.
    bool free(int me, double px, double py) {
      for (var o = 0; o < ids.length; o++) {
        if (o != me && room(x[o] - px, y[o] - py) < 0.98) return false;
      }
      for (final f in fixed) {
        if (room(f.dx - px, f.dy - py) < 0.98) return false;
      }
      return true;
    }

    var all = true;
    for (var i = 0; i < ids.length; i++) {
      if (free(i, x[i], y[i])) continue;
      double? bx, by, bd;
      for (var py = minY; py <= maxY + 0.01; py += ay / 2) {
        for (var px = minX; px <= maxX + 0.01; px += ax / 2) {
          if (!free(i, px, py)) continue;
          final dd = (px - x[i]) * (px - x[i]) + (py - y[i]) * (py - y[i]);
          if (bd == null || dd < bd) {
            bx = px;
            by = py;
            bd = dd;
          }
        }
      }
      if (bx != null && by != null) {
        x[i] = bx;
        y[i] = by;
      } else {
        all = false;
      }
    }
    return ({for (var i = 0; i < ids.length; i++) ids[i]: Offset(x[i], y[i])}, all);
  }

  /// [apart] once per [key] (people + size + radius); small LRU.
  static Map<String, Offset> cached(String key, Map<String, Offset> Function() make) {
    final hit = _cache.remove(key);
    if (hit != null) {
      _cache[key] = hit;
      return hit;
    }
    final v = make();
    _cache[key] = v;
    while (_cache.length > 16) {
      _cache.remove(_cache.keys.first);
    }
    return v;
  }

  static void clearCache() {
    _cache.clear();
    LinkRoute291._cache.clear();
  }
}

/// Bundle 291 (B-4): picks the bow of each line. The first try is always
/// today's 217 line; only a line that would run under a third person's photo
/// ([clear] px) or lie on another line (middles closer than [midGap]) bows
/// the other way / less / more.
class LinkRoute291 {
  LinkRoute291._(this.obstacles, this.clear, this.midGap);

  final List<Offset> obstacles;
  final double clear;
  final double midGap;
  final List<Offset> _mids = [];
  final Map<String, Offset> _picked = {};

  static final Map<String, LinkRoute291> _cache = {};

  /// One router per map picture ([key] = people + size + lines); the same
  /// lines in the same order get the same bows every frame.
  static LinkRoute291 of(String key,
      {required List<Offset> obstacles, required double clear, double midGap = 16}) {
    final hit = _cache.remove(key);
    if (hit != null) {
      _cache[key] = hit;
      return hit;
    }
    final r = LinkRoute291._(obstacles, clear, midGap);
    _cache[key] = r;
    while (_cache.length > 16) {
      _cache.remove(_cache.keys.first);
    }
    return r;
  }

  /// Same maths as `LinkPathsCanvas.aerialControl` (217).
  static Offset control(Offset p, Offset q, Offset centre, double k) {
    final d = q - p;
    final len = math.max(1.0, d.distance);
    final mid = Offset((p.dx + q.dx) / 2, (p.dy + q.dy) / 2);
    var n = Offset(-d.dy / len, d.dx / len);
    final o = mid - centre;
    if (o.distance < 1) {
      if (n.dy > 0) n = -n;
    } else if (o.dx * n.dx + o.dy * n.dy < 0) {
      n = -n;
    }
    return mid + n * (k * len);
  }

  static Offset point(Offset p, Offset c, Offset q, double t) {
    final u = 1 - t;
    return p * (u * u) + c * (2 * u * t) + q * (t * t);
  }

  /// The centre mirrored through the middle of p-q: the line bows the other way.
  static Offset flip(Offset p, Offset q, Offset centre) {
    final mid = Offset((p.dx + q.dx) / 2, (p.dy + q.dy) / 2);
    if ((mid - centre).distance < 1) return mid - const Offset(0, 10);
    return mid * 2 - centre;
  }

  /// Control point for the line p -> q (first choice: [k] around [centre]).
  Offset pick(Offset p, Offset q, Offset centre, double k) {
    final id = '${p.dx.toStringAsFixed(1)},${p.dy.toStringAsFixed(1)}>'
        '${q.dx.toStringAsFixed(1)},${q.dy.toStringAsFixed(1)}@'
        '${centre.dx.toStringAsFixed(1)},${centre.dy.toStringAsFixed(1)}/$k';
    final had = _picked[id];
    if (had != null) return had;
    final ks = <double>[k, k * 0.55, k * 1.4, 0.12];
    final tries = <(Offset, double)>[
      for (final b in ks) ...[(centre, b), (flip(p, q, centre), b)],
    ];
    Offset? best;
    Offset? bestMid;
    var bestScore = -1.0;
    for (final (c0, b) in tries) {
      final c = control(p, q, c0, b);
      var near = double.infinity;
      for (var s = 1; s < 24; s++) {
        final at = point(p, c, q, s / 24);
        for (final o in obstacles) {
          if ((o - p).distance < 1 || (o - q).distance < 1) continue; // the ends
          near = math.min(near, (at - o).distance);
        }
      }
      final m = point(p, c, q, 0.5);
      var other = double.infinity;
      for (final o in _mids) {
        other = math.min(other, (m - o).distance);
      }
      final score = math.min(near / clear, other / midGap);
      if (score > bestScore + 1e-9) {
        bestScore = score;
        best = c;
        bestMid = m;
      }
      if (near >= clear && other >= midGap) {
        best = c;
        bestMid = m;
        break;
      }
    }
    _mids.add(bestMid!);
    _picked[id] = best!;
    return best;
  }
}
