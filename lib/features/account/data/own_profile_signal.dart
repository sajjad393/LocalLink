import 'package:flutter/foundation.dart';

/// Bundle 207 (H1): bumped when I save my profile (name / picture), so the
/// Settings card and other "me" places reload at once.
class OwnProfileSignal {
  OwnProfileSignal._();

  static final ValueNotifier<int> changed = ValueNotifier<int>(0);

  static void bump() => changed.value++;
}
