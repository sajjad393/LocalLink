import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/admin/data/admin_permissions.dart';

void main() {
  test('Admin permissions match the backend role matrix', () {
    expect(AdminPermissions.canRead('owner'), isTrue);
    expect(AdminPermissions.canRead('operator'), isTrue);
    expect(AdminPermissions.canRead('security'), isTrue);
    expect(AdminPermissions.canRead('auditor'), isTrue);

    expect(AdminPermissions.canManageUsers('owner'), isTrue);
    expect(AdminPermissions.canManageUsers('operator'), isFalse);
    expect(AdminPermissions.canManageUsers('security'), isFalse);
    expect(AdminPermissions.canManageUsers('auditor'), isFalse);

    expect(AdminPermissions.canManageDevices('owner'), isTrue);
    expect(AdminPermissions.canManageDevices('operator'), isTrue);
    expect(AdminPermissions.canManageDevices('security'), isFalse);

    expect(AdminPermissions.canManageNetworkPolicy('owner'), isTrue);
    expect(AdminPermissions.canManageNetworkPolicy('operator'), isTrue);
    expect(AdminPermissions.canManageNetworkPolicy('security'), isFalse);
    expect(AdminPermissions.canManageNetworkPolicy('auditor'), isFalse);

    expect(AdminPermissions.canManageRecovery('owner'), isTrue);
    expect(AdminPermissions.canManageRecovery('operator'), isTrue);
    expect(AdminPermissions.canManageRecovery('security'), isTrue);
    expect(AdminPermissions.canManageRecovery('auditor'), isFalse);

    expect(AdminPermissions.canManageSessions('owner'), isTrue);
    expect(AdminPermissions.canManageSessions('operator'), isFalse);
    expect(AdminPermissions.canManageSessions('security'), isFalse);
    expect(AdminPermissions.canManageSettings('owner'), isTrue);
    expect(AdminPermissions.canManageSettings('operator'), isFalse);
    expect(AdminPermissions.canBackup('owner'), isTrue);
    expect(AdminPermissions.canBackup('auditor'), isFalse);
  });
}
