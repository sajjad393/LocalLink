/// Bundle 180: "tap Chats 5 times fast" - true on the 5th tap within 3 s.
class TapBurstCounter {
  TapBurstCounter({this.taps = 5, this.window = const Duration(seconds: 3)});

  final int taps;
  final Duration window;
  final List<DateTime> _times = <DateTime>[];

  bool tap([DateTime? now]) {
    final t = now ?? DateTime.now();
    _times.add(t);
    _times.removeWhere((x) => t.difference(x) > window || t.isBefore(x));
    if (_times.length >= taps) {
      _times.clear();
      return true;
    }
    return false;
  }
}
