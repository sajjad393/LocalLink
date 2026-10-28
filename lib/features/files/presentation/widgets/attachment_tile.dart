import 'dart:io';
import 'dart:async';
import 'package:flutter/services.dart';

import 'package:flutter/material.dart';

import 'package:locallink/core/widgets/error_toast.dart';
import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/features/files/data/models/file_transfer_models.dart';
import 'package:locallink/features/files/domain/file_transfer_repository_contract.dart';
import 'package:locallink/features/files/bloc/file_transfer_bloc.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/core/widgets/local_link_bloc_builder.dart';

class AttachmentTile extends StatefulWidget {
  final Attachment attachment;
  final FileTransferRepositoryContract transfer;
  final String messageId;
  final String? groupMessageId;

  /// Outgoing bubbles show a circular upload ring over the image while the
  /// outbox is still flushing this message (WhatsApp-style affordance).
  final bool uploading;

  const AttachmentTile({
    super.key,
    required this.attachment,
    required this.transfer,
    required this.messageId,
    this.groupMessageId,
    this.uploading = false,
  });

  @override
  State<AttachmentTile> createState() => _AttachmentTileState();
}

class _AttachmentTileState extends State<AttachmentTile> {
  late final FileTransferBloc _controller;
  String? _localPath;
  String? _displayPath;
  String? _activeOperation;
  bool _playing = false;
  int _audioDurationMs = 0;
  int _audioPositionMs = 0;
  Timer? _audioTimer;

  @override
  void initState() {
    super.initState();
    _localPath = widget.attachment.localPath;
    _controller = FileTransferBloc(repository: widget.transfer);
    _prepareExistingPath();
    _maybeAutoDownload();
  }

  /// WhatsApp behaviour: small media starts downloading the moment the
  /// bubble is shown — no tap needed. Manual tap remains for large files.
  bool get _isAudio {
    final mime = widget.attachment.contentType.toLowerCase();
    if (mime.startsWith('audio/')) return true;
    final name = widget.attachment.originalName.toLowerCase();
    return name.endsWith('.m4a') ||
        name.endsWith('.aac') ||
        name.endsWith('.mp3') ||
        name.endsWith('.wav') ||
        name.endsWith('.ogg') ||
        name.endsWith('.opus');
  }

  void _maybeAutoDownload() {
    final cached = _localPath;
    final hasLocal = cached != null && cached.isNotEmpty;
    if (hasLocal || widget.uploading) return;
    // Auto-fetch anything small: images AND voice notes (WhatsApp parity).
    final inlineCandidate = widget.attachment.isImage || _isAudio;
    if (inlineCandidate && widget.attachment.size <= 10 * 1024 * 1024) {
      // Post-frame so the tile's own progress state binds first.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _activeOperation == null) _download();
      });
    }
  }

  Future<void> _prepareExistingPath() async {
    final path = _localPath;
    if (path == null || path.isEmpty) return;
    try {
      var localPath = path;
      if (!await widget.transfer.isProtectedLocalFile(localPath)) {
        localPath = await widget.transfer.protectLegacyLocalFile(localPath);
        if (mounted) setState(() => _localPath = localPath);
      }
      final ext = widget.attachment.originalName.contains('.')
          ? '.${widget.attachment.originalName.split('.').last}'
          : '.bin';
      final view = await widget.transfer
          .materializeForDisplay(localPath, extension: ext);
      if (!mounted) {
        await widget.transfer.deleteLocalFile(view);
        return;
      }
      setState(() => _displayPath = view);
    } catch (error) {
      // Bundle 133+: never degrade silently again — this catch was pinning
      // the sender's OWN media behind a download icon with zero diagnostics
      // (the voice-note/video screenshot bug).
      AppLogger.error('ATTACHMENT_PREPARE_FAILED',
          error: error, detail: 'file=${widget.attachment.id}');
      if (mounted) setState(() => _displayPath = null);
    }
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  TransferProgress? get _progress {
    final id = _activeOperation;
    if (id == null) return null;
    return _controller.progressOf(id);
  }


  Future<void> _download() async {
    try {
      // The controller creates the operation id internally; the local view
      // observes the newest operation after each state notification.
      final future = _controller.download(
        widget.attachment,
        messageId: widget.messageId,
        groupMessageId: widget.groupMessageId,
      );
      await Future<void>.delayed(Duration.zero);
      if (mounted) {
        final latest = _controller.operations
            .where((item) => item.status == FileTransferStatus.running)
            .toList();
        if (latest.isNotEmpty) _activeOperation = latest.last.operationId;
        setState(() {});
      }
      final path = await future;
      final ext = widget.attachment.originalName.contains('.')
          ? '.${widget.attachment.originalName.split('.').last}'
          : '.bin';
      final view =
          await widget.transfer.materializeForDisplay(path, extension: ext);
      if (!mounted) {
        await widget.transfer.deleteLocalFile(view);
        return;
      }
      setState(() {
        _localPath = path;
        _displayPath = view;
        _activeOperation = null;
      });
    } on FileTransferCancelledException {
      if (mounted) setState(() => _activeOperation = null);
    } catch (error) {
      if (mounted) {
        setState(() => _activeOperation = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyErrorMessage(error))),
        );
      }
    }
  }

  Future<void> _cancel() async {
    final id = _activeOperation;
    if (id == null) return;
    await _controller.cancel(id);
    if (mounted) setState(() => _activeOperation = null);
  }

  /// Bundle 133+: a file that lives on THIS device must never download
  /// itself. Tap retries the protected local render instead of hitting the
  /// network for our own bytes.
  Future<void> _openOrRetryLocal() async {
    final local = _localPath;
    if (local == null || local.isEmpty) return;
    await _prepareExistingPath();
  }

  Future<void> _toggleAudio() async {
    if (_displayPath == null) {
      final local = _localPath;
      if (local != null && local.isNotEmpty) {
        // Local file exists but the protected render failed once — retry
        // that instead of downloading our own bytes back.
        _prepareExistingPath();
        return;
      }
      await _download();
      return;
    }
    try {
      const channel = MethodChannel('locallink/voice_notes');
      if (_playing) {
        await channel.invokeMethod('pause');
        _audioTimer?.cancel();
        if (mounted) setState(() => _playing = false);
      } else {
        final duration = await channel.invokeMethod<int>('play', {'path': _displayPath});
        final durationMs = duration ?? 0;
        _audioTimer?.cancel();
        if (mounted) {
          setState(() {
            _playing = true;
            _audioDurationMs = durationMs;
          });
        }
        if (durationMs > 0) {
          _audioTimer = Timer.periodic(const Duration(milliseconds: 120),
              (timer) {
            if (!mounted) { timer.cancel(); return; }
            setState(() {
              _audioPositionMs += 120;
              if (_audioPositionMs >= durationMs) {
                _audioPositionMs = 0;
                _playing = false;
                timer.cancel();
              }
            });
          });
        }
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
    }
  }

  String _fmtClock(int ms) {
    final total = (ms / 1000).floor();
    final m = total ~/ 60;
    final s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    final view = _displayPath;
    if (view != null && view.isNotEmpty) {
      widget.transfer.deleteLocalFile(view);
    }
    _audioTimer?.cancel();
    if (_playing) { const MethodChannel('locallink/voice_notes').invokeMethod('stop'); }
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LocalLinkBlocBuilder(
        bloc: _controller,
        builder: (context, state) {
          final displayPath = _displayPath;
          if (displayPath != null && File(displayPath).existsSync()) {
            if (widget.attachment.isImage) {
              return _imageWithUploadOverlay(displayPath);
            }
          }

          final progress = _progress;
          final running = progress?.status == FileTransferStatus.running;
          if (_isAudio) {
            final colors = Theme.of(context).colorScheme;
            final totalMs = _audioDurationMs > 0 ? _audioDurationMs : 0;
            final playbackFraction = totalMs > 0
                ? (_audioPositionMs / totalMs).clamp(0.0, 1.0)
                : 0.0;
            final label = (_playing || _audioPositionMs > 0) && totalMs > 0
                ? '${_fmtClock(_audioPositionMs)} / ${_fmtClock(totalMs)}'
                : (totalMs > 0
                    ? _fmtClock(totalMs)
                    : _sizeLabel(widget.attachment.size));
            return Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 42,
                    height: 42,
                    child: running
                        ? Stack(
                            alignment: Alignment.center,
                            children: [
                              CircularProgressIndicator(
                                value: _progress?.fraction,
                                strokeWidth: 3,
                              ),
                              IconButton(
                                tooltip: 'Cancel download',
                                onPressed: _cancel,
                                icon: const Icon(Icons.close, size: 18),
                              ),
                            ],
                          )
                        : Material(
                            color: colors.primary,
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: _toggleAudio,
                              child: Center(
                                child: Icon(
                                  _playing
                                      ? Icons.pause_rounded
                                      : (_displayPath == null &&
                                              (_localPath == null ||
                                                  _localPath!.isEmpty)
                                          ? Icons.download_rounded
                                          : Icons.play_arrow_rounded),
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Faux waveform — uniform bars that fill left→right
                        // with playback progress.
                        Row(
                          children: [
                            for (var i = 0; i < 24; i++)
                              Expanded(
                                child: Container(
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 1),
                                  height: 8 + 10 * ((i * 7 % 11) / 10),
                                  decoration: BoxDecoration(
                                    color: (i / 24) <= playbackFraction
                                        ? colors.primary
                                        : colors.onSurfaceVariant
                                            .withOpacity(.35),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          label,
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }
          return Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            child: Row(
              children: [
                Icon(widget.attachment.isImage
                    ? Icons.image
                    : Icons.insert_drive_file),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.attachment.originalName,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(_sizeLabel(widget.attachment.size),
                          style: Theme.of(context).textTheme.labelSmall),
                      if (progress?.error != null)
                        Text(
                          progress!.error!,
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(
                                  color: Theme.of(context).colorScheme.error),
                        ),
                    ],
                  ),
                ),
                if (running)
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          value: progress?.fraction,
                          strokeWidth: 3,
                        ),
                        IconButton(
                          tooltip: 'Cancel download',
                          onPressed: _cancel,
                          icon: const Icon(Icons.close, size: 18),
                        ),
                      ],
                    ),
                  )
                else
                  IconButton(
                    tooltip: _displayPath == null &&
                            (_localPath == null || _localPath!.isEmpty)
                        ? 'Download'
                        : (widget.attachment.contentType
                                .toLowerCase()
                                .startsWith('video/')
                            ? 'Play'
                            : 'Open'),
                    onPressed: _displayPath == null &&
                            (_localPath == null || _localPath!.isEmpty)
                        ? _download
                        : _openOrRetryLocal,
                    icon: Icon(_displayPath == null &&
                            (_localPath == null || _localPath!.isEmpty)
                        ? Icons.download_rounded
                        : (widget.attachment.contentType
                                .toLowerCase()
                                .startsWith('video/')
                            ? Icons.play_circle_outline_rounded
                            : Icons.file_open_rounded)),
                  ),
              ],
            ),
          );
        });
  }

  /// Outgoing affordance: while [AttachmentTile.uploading] is true the image
  /// local copy is shown dimmed with a circular upload ring on top — the same
  /// pattern as the receiver's download ring below.
  _imageWithUploadOverlay(String displayPath) {
    final uploading = widget.uploading;
    // Natural aspect: use stored EXIF dims when known; never stretch.
    final w = widget.attachment.width;
    final h = widget.attachment.height;
    const maxW = 250.0;
    final double imgW = (w > 0 && h > 0) ? maxW : maxW;
    final double imgH = (w > 0 && h > 0)
        ? (maxW * h / w).clamp(140.0, 360.0)
        : 180.0;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: imgW,
          height: imgH,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.file(File(displayPath), fit: BoxFit.cover),
              if (uploading)
                Container(
                  color: Colors.black38,
                  child: Center(
                    child: SizedBox(
                      width: 72,
                      height: 72,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircularProgressIndicator(
                            // Indeterminate: outbox flush doesn't expose a
                            // per-byte upload stream; the ring still signals
                            // "sending" truthfully while queued/uploading.
                            value: null,
                            strokeWidth: 4,
                            color: Colors.white,
                            backgroundColor: Colors.white30,
                          ),
                          const Icon(Icons.arrow_upward_rounded,
                              color: Colors.white, size: 28),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _sizeLabel(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
