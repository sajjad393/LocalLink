class Attachment {
  final String id;
  final String originalName;
  final String contentType;
  final int size;
  final String sha256;
  final int width;
  final int height;
  final bool isImage;
  final String? downloadUrl;
  final String? thumbnailUrl;
  final String? localPath;

  const Attachment({
    required this.id,
    required this.originalName,
    required this.contentType,
    required this.size,
    required this.sha256,
    this.width = 0,
    this.height = 0,
    this.isImage = false,
    this.downloadUrl,
    this.thumbnailUrl,
    this.localPath,
  });

  factory Attachment.fromJson(Map<String, dynamic> json, {String? localPath}) => Attachment(
        id: json['id']?.toString() ?? '',
        originalName: json['original_name']?.toString() ?? 'attachment',
        contentType: json['content_type']?.toString() ?? 'application/octet-stream',
        size: int.tryParse(json['size']?.toString() ?? '') ?? 0,
        sha256: json['sha256']?.toString() ?? '',
        width: int.tryParse(json['width']?.toString() ?? '') ?? 0,
        height: int.tryParse(json['height']?.toString() ?? '') ?? 0,
        isImage: json['is_image'] == true,
        downloadUrl: json['download_url']?.toString(),
        thumbnailUrl: json['thumbnail_url']?.toString(),
        localPath: localPath ?? json['local_path']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'original_name': originalName,
        'content_type': contentType,
        'size': size,
        'sha256': sha256,
        'width': width,
        'height': height,
        'is_image': isImage,
        if (downloadUrl != null) 'download_url': downloadUrl,
        if (thumbnailUrl != null) 'thumbnail_url': thumbnailUrl,
        if (localPath != null) 'local_path': localPath,
      };

  Attachment copyWith({
    String? id,
    String? localPath,
    String? sha256,
    int? size,
    String? downloadUrl,
    String? thumbnailUrl,
  }) => Attachment(
        id: id ?? this.id,
        originalName: originalName,
        contentType: contentType,
        size: size ?? this.size,
        sha256: sha256 ?? this.sha256,
        width: width,
        height: height,
        isImage: isImage,
        downloadUrl: downloadUrl ?? this.downloadUrl,
        thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
        localPath: localPath ?? this.localPath,
      );
}

class PickedFile {
  final String path;
  final String name;
  final String contentType;
  final int size;

  const PickedFile({required this.path, required this.name, required this.contentType, required this.size});
}
