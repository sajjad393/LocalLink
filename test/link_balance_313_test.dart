// Bundle 313 (B): a person straight above You (one offline friend on the
// upper arc, cos 270 deg = -1.8e-16) counts on NEITHER side, so two local
// Wi-Fi friends are split one each side (before: both stayed on the right
// and one line ran under the other name).
import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/admin/presentation/widgets/link_balance_298.dart';

void main() {
  const size = Size(318, 110);
  final s = Offset(size.width / 2, size.height * 0.62);

  test('offline one straight above + 2 local Wi-Fi: one each side of You', () {
    // You's x minus a rounding speck (on the phone: cos 270 deg * radius).
    expect(math.cos(270 * math.pi / 180), isNot(0.0));
    final above = Offset(s.dx - 1e-7, s.dy - 46);
    expect(above.dx, lessThan(s.dx));
    final place = <String, Offset>{
      'sumaira': above, // offline: not movable
      'kiran': Offset(s.dx + 60, s.dy + 20),
      'ayesha': Offset(s.dx + 100, s.dy + 25),
    };
    final out = LinkBalance298.balance(place, size, self: s, movable: {'kiran', 'ayesha'});
    final left = ['kiran', 'ayesha'].where((id) => out[id]!.dx < s.dx).length;
    final right = ['kiran', 'ayesha'].where((id) => out[id]!.dx > s.dx).length;
    expect(left, 1);
    expect(right, 1);
    expect(out['sumaira'], place['sumaira'], reason: 'offline stays where it is');
    // same input = same map
    expect(LinkBalance298.balance(place, size, self: s, movable: {'kiran', 'ayesha'}), out);
  });

  test('regression: a person clearly on the left still counts as left', () {
    final place = <String, Offset>{
      'srv': Offset(s.dx - 90, s.dy - 30), // server: not movable
      'kiran': Offset(s.dx + 60, s.dy + 20),
    };
    final out = LinkBalance298.balance(place, size, self: s, movable: {'kiran'});
    expect(out['kiran']!.dx, greaterThan(s.dx), reason: '1 left / 1 right is balanced');
  });
}
