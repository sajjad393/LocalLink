import 'dart:io';
import 'dart:async';
import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/features/files/data/models/file_transfer_models.dart';
import 'package:locallink/features/files/domain/file_transfer_repository_contract.dart';
import 'package:locallink/features/files/bloc/file_transfer_bloc.dart';
import 'package:locallink/core/widgets/local_link_bloc_builder.dart';

class AttachmentTile extends StatefulWidget {
  final Attachment attachment;
  final FileTransferRepositoryContract transfer;
  final String messageId;
  final String? groupMessageId;

  const AttachmentTile({
    super.key,
    required this.attachment,
    required this.transfer,
    required this.messageId,
    this.groupMessageId,
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
  Timer? _audioTimer;

  @override
  void initState() {
    super.initState();
    _localPath = widget.attachment.localPath;
    _controller = FileTransferBloc(repository: widget.transfer);
    _prepareExistingPath();
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
    } catch (_) {
      // Do not render an unprotected legacy file. The attachment remains
      // unavailable until it can be migrated into the protected format.
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
          SnackBar(
              content: Text(error.toString().replaceFirst('Exception: ', ''))),
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

  Future<void> _toggleAudio() async {
    if (_displayPath == null) { await _download(); return; }
    try {
      const channel = MethodChannel('locallink/voice_notes');
      if (_playing) {
        await channel.invokeMethod('pause');
        _audioTimer?.cancel();
        if (mounted) setState(() => _playing = false);
      } else {
        final duration = await channel.invokeMethod<int>('play', {'path': _displayPath});
        _audioTimer?.cancel();
        final durationMs = duration ?? 0;
        if (mounted) setState(() { _playing = true; _audioDurationMs = durationMs; });
        if (durationMs > 0) { _audioTimer = Timer(Duration(milliseconds: durationMs), () { if (mounted) setState(() => _playing = false); }); }
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))));
    }
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
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    File(displayPath),
                    width: 250,
                    height: 180,
                    fit: BoxFit.cover,
                  ),
                ),
              );
            }
          }

          final progress = _progress;
          final running = progress?.status == FileTransferStatus.running;
          if (widget.attachment.contentType.startsWith('audio/')) {
            return Card(
              child: ListTile(
                leading: CircleAvatar(child: Icon(_playing ? Icons.pause_rounded : Icons.mic_none_rounded)),
                title: Text(widget.attachment.originalName, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(_audioDurationMs > 0 ? '${(_audioDurationMs / 1000).ceil()} sec' : _sizeLabel(widget.attachment.size)),
                trailing: IconButton(tooltip: _playing ? 'Pause voice note' : (_displayPath == null ? 'Download voice note' : 'Play voice note'), onPressed: running ? _cancel : _toggleAudio, icon: Icon(running ? Icons.close : (_playing ? Icons.pause : (_displayPath == null ? Icons.download : Icons.play_arrow)))),
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
                      if (running)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: LinearProgressIndicator(
                              value: progress?.fraction),
                        ),
                    ],
                  ),
                ),
                if (running)
                  IconButton(
                    tooltip: 'Cancel download',
                    onPressed: _cancel,
                    icon: const Icon(Icons.close),
                  )
                else
                  IconButton(
                      onPressed: _download, icon: const Icon(Icons.download)),
              ],
            ),
          );
        });
  }

  String _sizeLabel(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
