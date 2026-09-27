import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/security/sensitive_file_protection_service.dart';

void main() {
  test(
      'sensitive lifecycle constants distinguish plaintext and protected temp files',
      () {
    expect(SensitiveFileProtectionService.plaintextPartSuffix, '.plain.part');
    expect(SensitiveFileProtectionService.protectedPartSuffix, '.enc.part');
    expect(SensitiveFileProtectionService.viewPrefix, '.view-');
  });

  test('malformed local paths cannot be treated as protected storage',
      () async {
    final service = SensitiveFileProtectionService();
    expect(await service.isProtected('/tmp/locallink-secret.enc'), isFalse);
    expect(
        await service.isProtected(
            '/data/data/com.sajjad.locallink/files/../shared/secret.enc'),
        isFalse);
  });

  test('cleanupSensitiveArtifacts only targets lifecycle temp patterns',
      () async {
    final service = SensitiveFileProtectionService();
    final root = await Directory.systemTemp.createTemp('locallink-sensitive-');
    addTearDown(() => root.delete(recursive: true));
    final view = File('${root.path}/.view-old.jpg');
    final plain = File('${root.path}/file.plain.part');
    final protectedPart = File('${root.path}/file.enc.part');
    final durable = File('${root.path}/durable.enc');
    await Future.wait([
      view.writeAsString('x'),
      plain.writeAsString('x'),
      protectedPart.writeAsString('x'),
      durable.writeAsString('x')
    ]);
    final stale = DateTime.now().subtract(const Duration(minutes: 10));
    for (final f in [view, plain, durable]) {
      await f.setLastModified(stale);
    }
    // Protected partial writes have a longer retention window (one hour).
    await protectedPart.setLastModified(
      DateTime.now().subtract(const Duration(hours: 2)),
    );
    await service.cleanupSensitiveArtifacts(root);
    expect(await view.exists(), isFalse);
    expect(await plain.exists(), isFalse);
    expect(await protectedPart.exists(), isFalse);
    expect(await durable.exists(), isTrue);
  });
}
