import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/features/files/data/models/file_transfer_models.dart';
import 'package:locallink/features/files/data/services/file_transfer_service.dart';
import 'package:locallink/features/files/domain/file_transfer_repository_contract.dart';

final class FileTransferRepository implements FileTransferRepositoryContract {
  final FileTransferService service;

  const FileTransferRepository({required this.service});

  @override
  Future<List<PickedFile>> pickFiles({
    String mimeType = '*/*',
    bool allowMultiple = false,
  }) =>
      service.pickFiles(mimeType: mimeType, allowMultiple: allowMultiple);

  @override
  Future<Attachment> upload(
    PickedFile file, {
    String? clientFileId,
    String? operationId,
    void Function(TransferProgress progress)? onProgress,
  }) =>
      service.upload(
        file,
        clientFileId: clientFileId,
        transferId: operationId,
        onProgress: onProgress,
      );

  @override
  Future<Attachment> uploadForMessage(
    PickedFile file, {
    required String recipientId,
    required String messageId,
    required String createdAt,
    required String clientFileId,
    String? operationId,
    void Function(TransferProgress progress)? onProgress,
  }) =>
      service.uploadForMessage(file,
          recipientId: recipientId,
          messageId: messageId,
          createdAt: createdAt,
          clientFileId: clientFileId,
          transferId: operationId,
          onProgress: onProgress);

  @override
  Future<Attachment> uploadForGroupMessage(
    PickedFile file, {
    required String groupId,
    required String messageId,
    required String createdAt,
    required String clientFileId,
    String? operationId,
    void Function(TransferProgress progress)? onProgress,
  }) =>
      service.uploadForGroupMessage(file,
          groupId: groupId,
          messageId: messageId,
          createdAt: createdAt,
          clientFileId: clientFileId,
          transferId: operationId,
          onProgress: onProgress);

  Future<void> sendDirectFile({
    required String recipientId,
    required String messageId,
    required String fileId,
    required PickedFile file,
  }) =>
      service.sendDirectFile(
        recipientId: recipientId,
        messageId: messageId,
        fileId: fileId,
        file: file,
      );

  @override
  Future<void> cancelDirectFile(String fileId) =>
      service.cancelDirectFile(fileId);

  @override
  Future<String> download(
    Attachment attachment, {
    String? operationId,
    void Function(TransferProgress progress)? onProgress,
    bool thumbnail = false,
  }) =>
      service.download(
        attachment,
        transferId: operationId,
        onProgress: onProgress,
        thumbnail: thumbnail,
      );

  @override
  Future<String> downloadForMessage(
    String messageId,
    Attachment attachment, {
    String? operationId,
    void Function(TransferProgress progress)? onProgress,
  }) =>
      service.downloadForMessage(
        messageId,
        attachment,
        transferId: operationId,
        onProgress: onProgress,
      );

  @override
  Future<String> downloadForGroupMessage(
    String messageId,
    Attachment attachment, {
    String? operationId,
    void Function(TransferProgress progress)? onProgress,
  }) =>
      service.downloadForGroupMessage(
        messageId,
        attachment,
        transferId: operationId,
        onProgress: onProgress,
      );

  @override
  Future<void> cancel(String operationId) => service.cancel(operationId);

  @override
  Future<void> deleteLocalFile(String path) => service.deleteLocalFile(path);

  @override
  Future<void> clearLocalCache() => service.clearLocalCache();

  @override
  Future<void> cleanupSensitiveViewCopies() =>
      service.cleanupSensitiveViewCopies();

  @override
  Future<void> cleanupSensitiveArtifacts() =>
      service.cleanupSensitiveArtifacts();

  @override
  Future<bool> isProtectedLocalFile(String path) =>
      service.isProtectedLocalFile(path);

  @override
  Future<String> protectLegacyLocalFile(String plaintextPath) =>
      service.protectLegacyLocalFile(plaintextPath);

  @override
  Future<String> materializeForDisplay(String protectedPath,
          {String extension = '.bin'}) =>
      service.materializeForDisplay(protectedPath, extension: extension);
}
