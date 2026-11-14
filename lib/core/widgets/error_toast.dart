import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:locallink/core/widgets/link_toast.dart';
import 'package:locallink/l10n/l10n.dart';

/// Bundle G2: an error whose [friendly] text can be shown as it is.
abstract interface class FriendlyError {
  String get friendly;
}

/// User-facing error policy: raw exceptions must never appear in the UI.
/// Surfaces whether a failure needs attention is a floating toast; anything
/// shown inline must pass through [friendlyErrorMessage] first.
String friendlyErrorMessage(Object? error) {
  // Bundle G2: errors that already carry plain words ("Only admins can do
  // this.").
  if (error is FriendlyError) return error.friendly;
  final text = error?.toString() ?? '';
  if (error is SocketException ||
      text.contains('SocketException') ||
      text.contains('Connection refused') ||
      text.contains('Network is unreachable')) {
    return L.t.noConnectionCheckYourNetworkAnd;
  }
  if (error is TimeoutException || text.contains('TimeoutException')) {
    return L.t.thatTookTooLongPleaseTry;
  }
  if (text.contains('401')) {
    return L.t.yourSessionHasExpiredPleaseLog;
  }
  if (text.contains('403')) {
    return L.t.thatActionIsNotAllowedOn;
  }
  if (text.contains('404')) {
    return L.t.notFoundItMayHaveBeen;
  }
  if (text.contains('409')) {
    return L.t.thatAlreadyExistsTryADifferent;
  }
  if (text.contains('413')) {
    return L.t.thatFileIsTooLargeTo;
  }
  if (text.contains('429')) {
    return L.t.tooManyAttemptsPleaseWaitA;
  }
  if (RegExp(r'5\d\d').hasMatch(text)) {
    return L.t.theServerIsHavingTroublePlease;
  }
  return L.t.somethingWentWrongPleaseTryAgain;
}

/// Transient top-anchored toast for failures (never leaks exception detail).
void showErrorToast(BuildContext context, {Object? error, String? message}) {
  // Bundle 289 (T-1): the same toast card as everywhere, with the red sign.
  LinkToast.show(context, message ?? friendlyErrorMessage(error), kind: LinkToastKind.error);
}
