/// Bundle 257 (A3): ask for the Wi-Fi Direct / Local Wi-Fi link keys to be
/// built and pushed again.
///
/// The link keys used to be pushed only when the transport started or the
/// friend list changed. A friend card that came later (fresh install, new
/// keys, "Accept new code", an account move) left the phone with no key for
/// that friend, and the friend's phone refused the link (10 Nov logs:
/// `LINK_AUTH keys peers=0` for 7 min on the C71).
///
/// The transport sets [onRequest]; the card / key code calls [request].
/// Never throws.
abstract final class LinkKeyRefresh257 {
  static void Function(String why)? onRequest;

  static void request(String why) {
    try {
      onRequest?.call(why);
    } catch (_) {}
  }
}
