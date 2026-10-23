import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/permissions/permission_gate_service.dart';

Map<String, Map<String, bool>> s(bool mic, bool nearby, [bool cam = false, bool ntf = false]) => {
      'microphone': {'granted': mic, 'can_request': true},
      'nearby': {'granted': nearby, 'can_request': true},
      'camera': {'granted': cam, 'can_request': true},
      'notifications': {'granted': ntf, 'can_request': true},
    };

void main() {
  group('bundle 94 gate rule', () {
    test('REQUIRED = microphone + nearby only; camera/notify irrelevant', () {
      // Gate stays open when a required one is missing.
      expect(PermissionGate.requiredSatisfied(s(false, true)), isFalse);
      expect(PermissionGate.requiredSatisfied(s(true, false)), isFalse);
      expect(PermissionGate.requiredSatisfied(s(false, false)), isFalse);
      // Both granted → satisfied REGARDLESS of camera/notifications.
      expect(PermissionGate.requiredSatisfied(s(true, true)), isTrue);
      expect(PermissionGate.requiredSatisfied(s(true, true, true, false)), isTrue);
    });

    test('empty/broken status map counts as missing (gate shows)', () {
      expect(PermissionGate.requiredSatisfied(const {}), isFalse);
      expect(PermissionGate.requiredSatisfied(const { 'microphone': {'granted': true}}), isFalse);
    });
  });
}
