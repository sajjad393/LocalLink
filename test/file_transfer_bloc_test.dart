import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/features/files/data/models/file_transfer_models.dart';
import 'package:locallink/features/files/domain/file_transfer_repository_contract.dart';
import 'package:locallink/features/files/bloc/file_transfer_bloc.dart';

class _FakeFileRepository implements FileTransferRepositoryContract {
  bool cancelled = false;
  @override
  Future<List<PickedFile>> pickFiles(
          {String mimeType = '*/*', bool allowMultiple = false}) async =>
      const [];
  @override
  Future<Attachment> upload(PickedFile file,
          {String? clientFileId,
          String? operationId,
          void Function(TransferProgress progress)? onProgress}) async =>
      throw UnimplementedError();
  @override
  Future<Attachment> uploadE2eForMessage(PickedFile file,
          {required String recipientId,
          required String messageId,
          required String createdAt,
          required String clientFileId,
          String? operationId,
          void Function(TransferProgress progress)? onProgress}) async =>
      throw UnimplementedError();
  @override
  Future<Attachment> uploadE2eForGroupMessage(PickedFile file,
          {required String groupId,
          required String messageId,
          required String createdAt,
          required String clientFileId,
          String? operationId,
          void Function(TransferProgress progress)? onProgress}) async =>
      throw UnimplementedError();
  @override
  Future<void> sendDirectFile(
      {required String recipientId,
      required String messageId,
      required String fileId,
      required PickedFile file}) async {}
  @override
  Future<String> download(Attachment attachment,
          {String? operationId,
          void Function(TransferProgress progress)? onProgress,
          bool thumbnail = false}) async =>
      '/tmp/file';
  @override
  Future<String> downloadForMessage(String messageId, Attachment attachment,
          {String? operationId,
          void Function(TransferProgress progress)? onProgress}) async =>
      '/tmp/file';
  @override
  Future<String> downloadForGroupMessage(
          String messageId, Attachment attachment,
          {String? operationId,
          void Function(TransferProgress progress)? onProgress}) async =>
      '/tmp/group-file';
  @override
  Future<void> cancel(String operationId) async {
    cancelled = true;
  }

  @override
  Future<void> cancelDirectFile(String fileId) async {
    cancelled = true;
  }

  @override
  Future<void> deleteLocalFile(String path) async {}
  @override
  Future<void> clearLocalCache() async {}
  @override
  Future<void> cleanupSensitiveViewCopies() async {}
  @override
  Future<void> cleanupSensitiveArtifacts() async {}
  @override
  Future<bool> isProtectedLocalFile(String path) async => false;
  @override
  Future<String> protectLegacyLocalFile(String plaintextPath) async =>
      plaintextPath;
  @override
  Future<String> materializeForDisplay(String protectedPath,
          {String extension = '.bin'}) async =>
      protectedPath;
}

void main() {
  test('FileTransferBloc tracks and clears finished operations', () async {
    final bloc = FileTransferBloc(repository: _FakeFileRepository());
    // The repository path is covered by the download operation and produces a completed state.
    const attachment = Attachment(
        id: 'a1',
        originalName: 'demo.txt',
        contentType: 'text/plain',
        size: 4,
        sha256: '');
    final path = await bloc.download(attachment, messageId: 'm1');
    expect(path, '/tmp/file');
    expect(bloc.operations.single.status, FileTransferStatus.completed);
    bloc.clearFinished();
    expect(bloc.operations, isEmpty);
    await bloc.close();
  });
}
