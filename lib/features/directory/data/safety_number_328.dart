import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Bundle 328 (phase 328 of the roadmap): the safety number of a contact.
///
/// Two people read the same 60 digits on both phones and compare them in
/// person. If they match, the keys really are each other's - nobody in the
/// middle. **No server, no internet, no timer:** the number is computed from
/// the two identity keys the phones already hold.
///
/// Rules kept simple on purpose:
/// * order does not matter - A comparing with B gets the same number as B
///   comparing with A (the two keys are sorted before hashing);
/// * the same two keys always give the same number;
/// * 12 groups of 5 digits, read like a phone number.
class SafetyNumber328 {
  /// The domain string: it must never change, or every number people have
  /// already compared would change with it.
  static const String domain = 'locallink-safety-328';

  static const int groupCount = 12;
  static const int digitsPerGroup = 5;
  static const int totalDigits = groupCount * digitsPerGroup; // 60

  /// The number for two identity keys (any order). Empty when a key is empty.
  static String of(String keyA, String keyB) {
    final a = keyA.trim();
    final b = keyB.trim();
    if (a.isEmpty || b.isEmpty) return '';

    // Sorted, so both phones hash the very same thing.
    final first = a.compareTo(b) <= 0 ? a : b;
    final second = a.compareTo(b) <= 0 ? b : a;

    var digest = sha256.convert(utf8.encode('$domain|$first|$second')).bytes;
    final bytes = <int>[...digest];
    var round = 0;
    // 12 groups need 48 bytes; one sha256 is 32, so chain a second round.
    while (bytes.length < groupCount * 4 && round < 8) {
      digest = sha256.convert([...digest, ++round]).bytes;
      bytes.addAll(digest);
    }

    final out = StringBuffer();
    for (var g = 0; g < groupCount; g++) {
      final i = g * 4;
      final v = (bytes[i] << 24) | (bytes[i + 1] << 16) | (bytes[i + 2] << 8) | bytes[i + 3];
      out.write((v % 100000).toString().padLeft(digitsPerGroup, '0'));
    }
    return out.toString();
  }

  /// 12 groups of 5 digits, for showing on the screen.
  static List<String> groups(String number) {
    if (number.length != totalDigits) return const [];
    return [
      for (var i = 0; i < groupCount; i++)
        number.substring(i * digitsPerGroup, (i + 1) * digitsPerGroup),
    ];
  }

  /// The words the user reads: "12345 67890 ..." in 3 rows of 4 groups.
  static List<String> rows(String number) {
    final g = groups(number);
    if (g.isEmpty) return const [];
    return [
      for (var i = 0; i < groupCount; i += 4) g.sublist(i, i + 4).join(' '),
    ];
  }

  /// How much of two numbers matches, in percent (100 = identical).
  /// Used when a person says "mine looks like 34 71 09 ..." - we can say how
  /// close it is without pretending it is the same.
  static int matchPercent(String a, String b) {
    if (a.length != totalDigits || b.length != totalDigits) return 0;
    var same = 0;
    for (var i = 0; i < totalDigits; i++) {
      if (a[i] == b[i]) same++;
    }
    return (same * 100 / totalDigits).round();
  }

  /// True when the string really is a 60 digit number.
  static bool looksValid(String number) =>
      number.length == totalDigits && RegExp(r'^[0-9]+$').hasMatch(number);

  /// Where this person cannot be checked yet: an honest sentence, never a fake
  /// number. (Their keys are not on this phone yet - common when offline.)
  static bool canCompare(String myKey, String theirKey) =>
      myKey.trim().isNotEmpty && theirKey.trim().isNotEmpty;
}
