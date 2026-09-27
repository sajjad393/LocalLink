enum FileTransferDirection { upload, download, direct }

enum FileTransferStatus { idle, queued, running, completed, failed, cancelled }

class TransferProgress {
  final String operationId;
  final FileTransferDirection direction;
  final int completed;
  final int total;
  final FileTransferStatus status;
  final String? error;

  const TransferProgress({
    required this.operationId,
    required this.direction,
    required this.completed,
    required this.total,
    required this.status,
    this.error,
  });

  double get fraction => total <= 0 ? 0.0 : (completed / total).clamp(0.0, 1.0).toDouble();

  TransferProgress copyWith({
    int? completed,
    int? total,
    FileTransferStatus? status,
    String? error,
    bool clearError = false,
  }) => TransferProgress(
        operationId: operationId,
        direction: direction,
        completed: completed ?? this.completed,
        total: total ?? this.total,
        status: status ?? this.status,
        error: clearError ? null : (error ?? this.error),
      );
}

class FileTransferCancelledException implements Exception {
  final String message;
  const FileTransferCancelledException([this.message = 'File transfer cancelled']);
  @override
  String toString() => message;
}
