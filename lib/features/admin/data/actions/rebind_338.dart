import 'package:flutter/foundation.dart' show ValueListenable;

import 'package:locallink/core/services/identity_key_upload_291.dart';

/// Bundle 338: one phone could not bind its key and nobody knew.
///
/// A real pair of phones: RMX5303 logged `IDENTITY_KEY_PUT bound (server has
/// another key)` three times and the server answered `identity key is already
/// bound` to every `PUT /api/v1/device-key`, while Z2453 said `ok`. 291 treated
/// that as settled - correct, a stolen token must not swap a key - but it never
/// told the owner, so every server feature was quietly off on that phone.
///
/// The rules here are pure so they can be checked: who sees the row, and when a
/// re-register may run. Nothing is sent without the owner tapping Send.
abstract final class Rebind338 {
  /// The server holds a different key for this phone.
  static const String bound = 'bound';

  /// The server holds this phone's key.
  static const String ok = 'ok';

  /// The row on the Security page: [bound] only. `''` means nothing is known
  /// yet (never connected), and [ok] means there is nothing to say.
  static bool needsRow(String state) => state == bound;

  /// A re-register replaces the key the server holds for the account, so it
  /// runs only when the owner said so AND the phone is really in [bound].
  static bool mayReRegister({required bool consented, required String state}) =>
      consented && state == bound;

  /// The state the Security page watches (the service owns it).
  static ValueListenable<String> get watch => IdentityKeyUpload291.boundDevice291;

  /// The re-register this phone was given (null = not wired yet).
  static Future<String> Function()? get reRegister => IdentityKeyUpload291.reRegister338;
}
