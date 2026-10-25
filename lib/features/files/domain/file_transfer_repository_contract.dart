import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/features/files/data/models/file_transfer_models.dart';

abstract interface class FileTransferRepositoryContract {
  Future<List<PickedFile>> pickFiles(
      {String mimeType = '*/*', bool allowMultiple = false});

  Future<Attachment> upload(
    PickedFile file, {
    String? clientFileId,
    String? operationId,
    void Function(TransferProgress progress)? onProgress,
  });

  Future<Attachment> uploadForMessage(
    PickedFile file, {
    required String recipientId,
    required String messageId,
    required String createdAt,
    required String clientFileId,
    String? operationId,
    void Function(TransferProgress progress)? onProgress,
  });

  Future<Attachment> uploadForGroupMessage(
    PickedFile file, {
    required String groupId,
    required String messageId,
    required String createdAt,
    required String clientFileId,
    String? operationId,
    void Function(TransferProgress progress)? onProgress,
  });

  Future<void> sendDirectFile({
    required String recipientId,
    required String messageId,
    required String fileId,
    required PickedFile file,
  });

  /// Copies a freshly picked outgoing attachment into app-private durable
  /// storage and returns the new path. Pickers hand back cache paths the OS
  /// can reclaim at any moment; the outbox must own a durable copy so the
  /// sender's preview renders and retry flushes (mesh or server) still find
  /// the bytes. Falls back to the original path when staging fails.
  Future<String> stageOutgoingFile({
    required PickedFile file,
    required String fileId,
  });

  Future<void> cancelDirectFile(String fileId);

  Future<String> download(
    Attachment attachment, {
    String? operationId,
    void Function(TransferProgress progress)? onProgress,
    bool thumbnail = false,
  });

  Future<String> downloadForMessage(
    String messageId,
    Attachment attachment, {
    String? operationId,
    void Function(TransferProgress progress)? onProgress,
  });

  Future<String> downloadForGroupMessage(
    String messageId,
    Attachment attachment, {
    String? operationId,
    void Function(TransferProgress progress)? onProgress,
  });

  Future<void> cancel(String operationId);
  Future<void> deleteLocalFile(String path);
  Future<void> clearLocalCache();
  Future<void> cleanupSensitiveViewCopies();
  Future<void> cleanupSensitiveArtifacts();
  Future<bool> isProtectedLocalFile(String path);
  Future<String> protectLegacyLocalFile(String plaintextPath);
  Future<String> materializeForDisplay(String protectedPath,
      {String extension = '.bin'});
}
