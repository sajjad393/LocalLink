/// Bundle 321 (L19b): Wi-Fi Direct self-repair.
///
/// 16-17 Nov: the Owner phone hosted / joined its own phone-to-phone group
/// while ON the server's Wi-Fi and then could not reach the server PC for
/// 30 min ("no route"); Wi-Fi off/on fixed it. The link between the two is
/// NOT VERIFIED, so this only repairs: when the server has not answered for
/// [lostMs] while THIS phone is in a group on Wi-Fi, the phone leaves its
/// own group ONCE per server loss and does not host a new group on this
/// Wi-Fi for [noHostMs] (joining others stays allowed). The app never turns
/// Wi-Fi on or off.
class ServerGroupRepair321 {
  static const int lostMs = 2 * 60 * 1000;
  static const int noHostMs = 15 * 60 * 1000;

  int _noHostUntil = 0;
  int _actedOn = 0; // the server-down time already acted on

  /// True = leave the own group now. [serverDownSince] is 0 while the
  /// server answers (or no server is set up).
  bool shouldDrop({
    required int now,
    required int serverDownSince,
    required bool inGroup,
    required bool onWifi,
  }) {
    if (serverDownSince <= 0 || !inGroup || !onWifi) return false;
    if (now - serverDownSince < lostMs) return false;
    if (_actedOn == serverDownSince) return false;
    _actedOn = serverDownSince;
    _noHostUntil = now + noHostMs;
    return true;
  }

  /// No new own group on this Wi-Fi yet.
  bool hostHeld({required int now, required bool onWifi}) => onWifi && now < _noHostUntil;
}
