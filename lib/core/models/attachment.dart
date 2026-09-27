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
  final String cryptoVersion;
  final String cryptoScope;
  final int cryptoKeyVersion;
  final String? cryptoNonce;
  final String? cryptoMac;
  final String? thumbnailCryptoNonce;
  final String? thumbnailCryptoMac;

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
    this.cryptoVersion = '',
    this.cryptoScope = '',
    this.cryptoKeyVersion = 0,
    this.cryptoNonce,
    this.cryptoMac,
    this.thumbnailCryptoNonce,
    this.thumbnailCryptoMac,
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
        cryptoVersion: json['crypto_version']?.toString() ?? '',
        cryptoScope: json['crypto_scope']?.toString() ?? '',
        cryptoKeyVersion: int.tryParse(json['crypto_key_version']?.toString() ?? '') ?? 0,
        cryptoNonce: json['crypto_nonce']?.toString(),
        cryptoMac: json['crypto_mac']?.toString(),
        thumbnailCryptoNonce: json['thumbnail_crypto_nonce']?.toString(),
        thumbnailCryptoMac: json['thumbnail_crypto_mac']?.toString(),
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
        if (cryptoVersion.isNotEmpty) 'crypto_version': cryptoVersion,
        if (cryptoScope.isNotEmpty) 'crypto_scope': cryptoScope,
        if (cryptoKeyVersion > 0) 'crypto_key_version': cryptoKeyVersion,
        if (cryptoNonce != null) 'crypto_nonce': cryptoNonce,
        if (cryptoMac != null) 'crypto_mac': cryptoMac,
        if (thumbnailCryptoNonce != null) 'thumbnail_crypto_nonce': thumbnailCryptoNonce,
        if (thumbnailCryptoMac != null) 'thumbnail_crypto_mac': thumbnailCryptoMac,
      };

  Attachment copyWith({
    String? id,
    String? localPath,
    String? sha256,
    int? size,
    String? downloadUrl,
    String? thumbnailUrl,
    String? cryptoVersion,
    String? cryptoScope,
    int? cryptoKeyVersion,
    String? cryptoNonce,
    String? cryptoMac,
    String? thumbnailCryptoNonce,
    String? thumbnailCryptoMac,
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
        cryptoVersion: cryptoVersion ?? this.cryptoVersion,
        cryptoScope: cryptoScope ?? this.cryptoScope,
        cryptoKeyVersion: cryptoKeyVersion ?? this.cryptoKeyVersion,
        cryptoNonce: cryptoNonce ?? this.cryptoNonce,
        cryptoMac: cryptoMac ?? this.cryptoMac,
        thumbnailCryptoNonce: thumbnailCryptoNonce ?? this.thumbnailCryptoNonce,
        thumbnailCryptoMac: thumbnailCryptoMac ?? this.thumbnailCryptoMac,
      );
}

class PickedFile {
  final String path;
  final String name;
  final String contentType;
  final int size;

  const PickedFile({required this.path, required this.name, required this.contentType, required this.size});
}
