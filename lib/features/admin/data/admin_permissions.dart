final class AdminPermissions {
  static bool canRead(String role) =>
      const {'owner', 'operator', 'security', 'auditor'}.contains(role);
  static bool canManageUsers(String role) => role == 'owner';
  static bool canManageDevices(String role) =>
      const {'owner', 'operator'}.contains(role);
  static bool canManageNetworkPolicy(String role) =>
      const {'owner', 'operator'}.contains(role);
  static bool canManageRecovery(String role) =>
      const {'owner', 'operator', 'security'}.contains(role);
  static bool canManageSessions(String role) => role == 'owner';
  static bool canManageSettings(String role) => role == 'owner';
  static bool canBackup(String role) => role == 'owner';
}
