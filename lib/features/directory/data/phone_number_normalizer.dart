class PhoneNumberNormalizer {
  const PhoneNumberNormalizer._();
  static String normalize(String input) {
    var raw = input.trim().replaceAll(RegExp(r'[\s()\-.]'), '');
    if (raw.startsWith('00')) raw = '+${raw.substring(2)}';
    if (raw.startsWith('03') && raw.length == 11) raw = '+92${raw.substring(1)}';
    if (raw.startsWith('923') && raw.length == 12) raw = '+$raw';
    if (!raw.startsWith('+')) return '';
    final digits = raw.substring(1);
    if (!RegExp(r'^\d{8,15}$').hasMatch(digits)) return '';
    return '+$digits';
  }
  static bool isValid(String value) => normalize(value).isNotEmpty;
}
