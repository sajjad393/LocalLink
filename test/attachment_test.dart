import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/attachment.dart';

void main() {
  test('attachment JSON round-trip preserves metadata', () {
    const source = Attachment(
      id: 'file-1',
      originalName: 'photo.jpg',
      contentType: 'image/jpeg',
      size: 1234,
      sha256: 'abc123',
      width: 800,
      height: 600,
      isImage: true,
      downloadUrl: '/api/v1/files/file-1/content',
      thumbnailUrl: '/api/v1/files/file-1/thumbnail',
      localPath: '/data/photo.jpg',
    );
    final decoded = Attachment.fromJson(source.toJson());
    expect(decoded.id, source.id);
    expect(decoded.originalName, source.originalName);
    expect(decoded.contentType, source.contentType);
    expect(decoded.size, source.size);
    expect(decoded.isImage, isTrue);
    expect(decoded.localPath, source.localPath);
  });
}
