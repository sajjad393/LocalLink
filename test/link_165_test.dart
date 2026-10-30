import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/connectivity/data/services/nearby_admin_status.dart';

// Bundle 165 (5.1): files through any LocalLink phone. The locking is
// native (Link165Test.kt); the app only shows the count in the admin view.
void main() {
  test('admin view reads file parts passed on for others', () {
    final s = NearbyAdminSnapshot.from(group: const {}, topology: const {
      'forwarded_voice_frames': 12,
      'forwarded_file_chunks': 345,
    });
    expect(s.forwardedFileChunks, 345);
    expect(s.forwardedVoiceFrames, 12);
  });

  test('older native side without the count shows 0', () {
    final s = NearbyAdminSnapshot.from(group: const {}, topology: const {});
    expect(s.forwardedFileChunks, 0);
  });
}
