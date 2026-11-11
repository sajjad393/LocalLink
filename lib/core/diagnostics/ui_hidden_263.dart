import 'package:locallink/core/services/app_logger.dart';

/// Bundle 263 (F7): a card / note that the user no longer sees (it was not
/// useful to a normal user) still leaves one log line, so the phone log
/// tells what the card used to say. Once per app start per card.
class UiHidden263 {
  UiHidden263._();

  static final Set<String> _done = <String>{};

  /// [card] e.g. carried, wait_server, publish, done, sync_notice,
  /// account_phone_only, add_status, signup_saved.
  static void note(String card, [String detail = '']) {
    if (card.isEmpty || !_done.add(card)) return;
    AppLogger.info('UI_HIDDEN_263',
        detail: detail.isEmpty ? 'card=$card' : 'card=$card $detail');
  }

  static bool noted(String card) => _done.contains(card);

  static void resetForTest() => _done.clear();
}
