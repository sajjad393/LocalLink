import 'package:equatable/equatable.dart';

class AdminSession extends Equatable {
  final String token;
  final String expiresAt;
  final String adminId;
  final String username;
  final String role;

  const AdminSession({
    required this.token,
    required this.expiresAt,
    required this.adminId,
    required this.username,
    required this.role,
  });

  factory AdminSession.fromLogin(Map<String, dynamic> json) {
    final admin = Map<String, dynamic>.from((json['admin'] as Map?) ?? const {});
    return AdminSession(
      token: json['token']?.toString() ?? '',
      expiresAt: json['expires_at']?.toString() ?? '',
      adminId: admin['id']?.toString() ?? '',
      username: admin['username']?.toString() ?? '',
      role: admin['role']?.toString() ?? '',
    );
  }

  bool get expired {
    final value = DateTime.tryParse(expiresAt);
    return token.isEmpty || value == null || !value.isAfter(DateTime.now().toUtc());
  }

  @override
  List<Object?> get props => [token, expiresAt, adminId, username, role];
}
