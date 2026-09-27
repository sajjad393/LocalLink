import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/admin/data/models/admin_session.dart';

void main() {
  test('AdminSession.fromLogin parses the server session payload', () {
    final session = AdminSession.fromLogin({
      'token': 'session-token',
      'expires_at': '2099-01-01T00:00:00Z',
      'admin': {
        'id': 'admin-1',
        'username': 'root',
        'role': 'owner',
      },
    });

    expect(session.token, 'session-token');
    expect(session.adminId, 'admin-1');
    expect(session.username, 'root');
    expect(session.role, 'owner');
    expect(session.expired, isFalse);
  });

  test('AdminSession rejects an expired or malformed session', () {
    expect(
      const AdminSession(
        token: 'token',
        expiresAt: '2000-01-01T00:00:00Z',
        adminId: 'admin-1',
        username: 'root',
        role: 'owner',
      ).expired,
      isTrue,
    );

    expect(
      const AdminSession(
        token: 'token',
        expiresAt: 'not-a-date',
        adminId: 'admin-1',
        username: 'root',
        role: 'owner',
      ).expired,
      isTrue,
    );

    expect(
      const AdminSession(
        token: '',
        expiresAt: '2099-01-01T00:00:00Z',
        adminId: 'admin-1',
        username: 'root',
        role: 'owner',
      ).expired,
      isTrue,
    );
  });
}
