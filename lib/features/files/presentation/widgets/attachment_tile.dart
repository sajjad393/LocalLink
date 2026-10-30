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
import 'package:locallink/features/files/data/services/media_progress_hub.dart';
import 'blue_progress_ring.dart';
import 'chat_photo.dart';
import 'chat_video_controller.dart';
import 'chat_video_player.dart';
import 'media_frame.dart';
import 'media_playback_coordinator.dart';
import 'media_view_cache.dart';

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
  // Bundle 147: the decrypted view comes from MediaViewCache (decrypted once,
  // shared, kept while shown). This tile holds one reference to it.
  String? _viewKey;
  // Bundle 150: one quiet retry when opening the local file fails.
  int _prepareFailures = 0;

  @override
  void initState() {
    super.initState();
    _localPath = widget.attachment.localPath;
    _controller = FileTransferBloc(repository: widget.transfer);
    _prepareExistingPath();
    _maybeAutoDownload();
  }

  /// Bundle 150: the message usually arrives BEFORE its file (Wi-Fi). When
  /// the file lands, the chat rebuilds this tile with the saved path — show
  /// it at once instead of waiting for a refresh.
  @override
  void didUpdateWidget(AttachmentTile old) {
    super.didUpdateWidget(old);
    final next = widget.attachment.localPath;
    if (next != null &&
        next.isNotEmpty &&
        next != old.attachment.localPath &&
        next != _localPath &&
        _displayPath == null) {
      AppLogger.info('ATTACHMENT_PATH_ARRIVED',
          detail: 'file=${widget.attachment.id}');
      _localPath = next;
      _prepareFailures = 0;
      unawaited(_prepareExistingPath());
    }
  }

  /// Bundle 150: still coming over Wi-Fi — no local file yet and no server
  /// link, so a server download can only fail ("Something went wrong").
  bool get _arrivingDirect {
    if (widget.uploading || widget.groupMessageId != null) return false;
    final local = _localPath;
    if (local != null && local.isNotEmpty) return false;
    final url = widget.attachment.downloadUrl;
    return url == null || url.isEmpty;
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

  /// Bundle 145: videos play inside the bubble.
  bool get _isVideo {
    final mime = widget.attachment.contentType.toLowerCase();
    if (mime.startsWith('video/')) return true;
    final name = widget.attachment.originalName.toLowerCase();
    return name.endsWith('.mp4') ||
        name.endsWith('.m4v') ||
        name.endsWith('.mov') ||
        name.endsWith('.3gp') ||
        name.endsWith('.webm') ||
        name.endsWith('.mkv');
  }

  String get _videoCacheKey => widget.attachment.id.isNotEmpty
      ? widget.attachment.id
      : widget.attachment.sha256;

  void _maybeAutoDownload() {
    final cached = _localPath;
    final hasLocal = cached != null && cached.isNotEmpty;
    if (hasLocal || widget.uploading) return;
    // Bundle 150: arriving over Wi-Fi — it shows by itself when it lands.
    if (_arrivingDirect) return;
    // Auto-fetch anything small: images, voice notes and (bundle 145)
    // videos up to 10 MB (WhatsApp parity). Bigger ones wait for a tap.
    final inlineCandidate = widget.attachment.isImage || _isAudio || _isVideo;
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
      final view = await _acquireView(localPath);
      if (view == null) return;
      setState(() => _displayPath = view);
    } catch (error) {
      // Bundle 150: the file can still be settling (just written / just
      // protected). Retry once quietly before giving up.
      if (_prepareFailures++ == 0) {
        Future<void>.delayed(const Duration(milliseconds: 800), () {
          if (mounted && _displayPath == null) {
            unawaited(_prepareExistingPath());
          }
        });
      }
      // Bundle 133+: never degrade silently again — this catch was pinning
      // the sender's OWN media behind a download icon with zero diagnostics
      // (the voice-note/video screenshot bug).
      AppLogger.error('ATTACHMENT_PREPARE_FAILED',
          error: error, detail: 'file=${widget.attachment.id}');
      if (mounted) setState(() => _displayPath = null);
    }
  }

  String get _ext => widget.attachment.originalName.contains('.')
      ? '.${widget.attachment.originalName.split('.').last}'
      : '.bin';

  /// Bundle 147: shared decrypted view for [protectedPath] (decryption runs
  /// off the UI thread). Returns null when this tile is already gone.
  Future<String?> _acquireView(String protectedPath) async {
    final key = '$protectedPath|$_ext';
    final view = await MediaViewCache.instance.acquire(
      key,
      () => widget.transfer.materializeForDisplay(protectedPath, extension: _ext),
      delete: widget.transfer.deleteLocalFile,
    );
    if (!mounted) {
      MediaViewCache.instance.release(key);
      return null;
    }
    if (_viewKey == key) {
      MediaViewCache.instance.release(key); // already holding this one
    } else {
      _releaseView();
      _viewKey = key;
    }
    return view;
  }

  void _releaseView() {
    final key = _viewKey;
    _viewKey = null;
    if (key != null) MediaViewCache.instance.release(key);
  }

  TransferProgress? get _progress {
    final id = _activeOperation;
    if (id == null) return null;
    return _controller.progressOf(id);
  }


  Future<void> _download() async {
    if (_arrivingDirect) {
      // Bundle 150: nothing to download from the server; it is on its way.
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
          content: Text('Still receiving over Wi-Fi. It will appear by itself.')));
      return;
    }
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
      final view = await _acquireView(path);
      if (view == null) return;
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
        // that instead of downloading our own bytes back. Bundle 144: then
        // play straight away (one tap, not two).
        await _prepareExistingPath();
        if (!mounted || _displayPath == null) return;
      } else {
        await _download();
        return;
      }
    }
    try {
      const channel = MethodChannel('locallink/voice_notes');
      if (_playing) {
        MediaPlaybackCoordinator.instance.release(this);
        await channel.invokeMethod('pause');
        _audioTimer?.cancel();
        if (mounted) setState(() => _playing = false);
      } else {
        // Bundle 145: one medium at a time; a playing video (or another
        // voice note) pauses first.
        MediaPlaybackCoordinator.instance.claim(this, _pauseAudioForOther);
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
                MediaPlaybackCoordinator.instance.release(this);
              }
            });
          });
        }
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
    }
  }

  void _pauseAudioForOther() {
    _audioTimer?.cancel();
    if (_playing) {
      unawaited(const MethodChannel('locallink/voice_notes')
          .invokeMethod('pause')
          .catchError((Object _) => null));
    }
    if (mounted) setState(() => _playing = false);
  }

  String _fmtClock(int ms) {
    final total = (ms / 1000).floor();
    final m = total ~/ 60;
    final s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    // Bundle 147: give the view back to the cache instead of deleting it,
    // so scrolling back shows it at once (no second decrypt).
    _releaseView();
    MediaPlaybackCoordinator.instance.release(this);
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
          // Bundle 147: no synchronous file check in build (it ran on every
          // frame while scrolling); the cache keeps shown views on disk.
          final displayPath = _displayPath;
          if (displayPath != null) {
            if (widget.attachment.isImage) {
              return ChatPhoto(
                key: ValueKey<String>(displayPath),
                path: displayPath,
                sizeKey: _videoCacheKey,
                hintWidth: widget.attachment.width,
                hintHeight: widget.attachment.height,
                uploading: widget.uploading,
                uploadOverlay: _sendOverlay(),
                title: widget.attachment.originalName,
              );
            }
            if (_isVideo) {
              // Bundle 145: inline player (same for sender and receiver).
              final viewKey = _viewKey;
              return ChatVideoPlayer(
                key: ValueKey<String>(displayPath),
                path: displayPath,
                cacheKey: _videoCacheKey,
                sizeBytes: widget.attachment.size,
                hintWidth: widget.attachment.width,
                hintHeight: widget.attachment.height,
                uploading: widget.uploading,
                uploadOverlay: _sendOverlay(),
                // Playing holds its own reference, so the video keeps going
                // in the mini player after this bubble is gone.
                onRetainFile: viewKey == null
                    ? null
                    : () => MediaViewCache.instance.retain(viewKey),
                onReleaseFile: viewKey == null
                    ? null
                    : (_) => MediaViewCache.instance.release(viewKey),
              );
            }
          }

          final progress = _progress;
          final running = progress?.status == FileTransferStatus.running;
          if (_isVideo) return _videoPlaceholder(progress, running);
          // Bundle 150: photos never fall back to the grey file row.
          if (widget.attachment.isImage) {
            return _photoPlaceholder(progress, running);
          }
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

  /// Bundle 145: video not viewable yet. Arriving: dimmed thumbnail (or
  /// grey), progress ring with X, "4.1 / 11.8 MB". Bigger than 10 MB:
  /// download button. Own file being prepared: play button.
  Widget _videoPlaceholder(TransferProgress? progress, bool running) {
    final cached = VideoInfoCache.peek(_videoCacheKey);
    final a = widget.attachment;
    final hint = a.width > 0 && a.height > 0 ? a.width / a.height : null;
    final size = ChatVideoPlayer.frameSize(cached?.aspectRatio ?? hint);
    final hasLocal = _localPath != null && _localPath!.isNotEmpty;
    Widget circle(IconData icon, String tip, VoidCallback onTap, Key key) =>
        Material(
          color: Colors.black54,
          shape: const CircleBorder(),
          child: InkWell(
            key: key,
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 56,
              height: 56,
              child: Tooltip(
                message: tip,
                child: Icon(icon, color: Colors.white, size: 32),
              ),
            ),
          ),
        );
    final Widget center;
    final ring = _ringCenter(progress, running);
    if (ring != null) {
      center = FittedBox(fit: BoxFit.scaleDown, child: ring);
    } else if (hasLocal || widget.uploading) {
      center = circle(Icons.play_arrow_rounded, 'Play', _openOrRetryLocal,
          const Key('chat_video_prepare'));
    } else {
      center = circle(Icons.download_rounded, 'Download', _download,
          const Key('chat_video_download'));
    }
    final thumb = cached?.thumbnail;
    // Bundle 150: the ring's own label shows "% · MB" while it runs.
    final sizeChip = ring == null ? _sizeLabel(a.size) : null;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Colors.black),
              if (thumb != null)
                Opacity(
                  opacity: .55,
                  child: Image.memory(thumb,
                      fit: BoxFit.cover, gaplessPlayback: true),
                )
              else
                ColoredBox(
                  color: const Color(0xFF2A2F3A),
                  child: Align(
                    alignment: const Alignment(0, -.6),
                    child: Icon(Icons.videocam_rounded,
                        color: Colors.white.withValues(alpha: .25), size: 30),
                  ),
                ),
              Center(child: center),
              if (cached != null && cached.durationMs > 0)
                Positioned(
                  left: 8,
                  bottom: 8,
                  child: VideoChip(
                    icon: Icons.videocam_rounded,
                    label: formatVideoClock(
                        Duration(milliseconds: cached.durationMs)),
                  ),
                ),
              if (sizeChip != null)
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: VideoChip(
                      key: const Key('chat_video_progress_chip'),
                      label: sizeChip),
                ),
              if (!running && progress?.error != null)
                Positioned(
                  left: 8,
                  right: 8,
                  top: 8,
                  child: Text(
                    progress!.error!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 11.5),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Bundle 150: blue ring for the middle of a photo/video bubble, or null
  /// when nothing is moving (then the bubble shows play / download).
  Widget? _ringCenter(TransferProgress? progress, bool running) {
    final size = widget.attachment.size;
    if (running) {
      final known = progress != null && progress.total > 0;
      final total = known ? progress.total : size;
      return BlueProgressRing(
        key: const Key('chat_media_download_ring'),
        fraction: known ? progress.fraction : null,
        label: mediaProgressLabel(progress?.completed ?? 0, total),
        onCancel: _cancel,
      );
    }
    if (_arrivingDirect) {
      return _LiveRing(
        key: const Key('chat_media_receiving'),
        messageId: widget.messageId,
        sizeBytes: size,
        icon: Icons.arrow_downward_rounded,
        idleLabel: _idle('Receiving…', size),
      );
    }
    if (widget.uploading) {
      return _LiveRing(
        key: const Key('chat_media_sending'),
        messageId: widget.messageId,
        sizeBytes: size,
        icon: Icons.arrow_upward_rounded,
        idleLabel: _idle('Sending…', size),
      );
    }
    return null;
  }

  String _idle(String text, int size) =>
      size > 0 ? '$text · ${_sizeLabel(size)}' : text;

  /// Bundle 150: drawn over the sender's own photo/video while it is sent.
  Widget _sendOverlay() => ColoredBox(
        color: Colors.black38,
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: _LiveRing(
              key: const Key('chat_media_sending'),
              messageId: widget.messageId,
              sizeBytes: widget.attachment.size,
              icon: Icons.arrow_upward_rounded,
              idleLabel: _idle('Sending…', widget.attachment.size),
            ),
          ),
        ),
      );

  /// Bundle 150: photo not viewable yet. Same frame as the photo (real
  /// shape when known), blue ring while it moves, never the grey file row.
  Widget _photoPlaceholder(TransferProgress? progress, bool running) {
    final a = widget.attachment;
    final known = MediaSizeCache.get(_videoCacheKey);
    final frame = known != null
        ? MediaFrame.fit(known.width, known.height)
        : MediaFrame.fit(a.width, a.height);
    final hasLocal = _localPath != null && _localPath!.isNotEmpty;
    final ring = _ringCenter(progress, running);
    Widget button(IconData icon, String tip, VoidCallback onTap, Key key) =>
        Material(
          color: Colors.black54,
          shape: const CircleBorder(),
          child: InkWell(
            key: key,
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 56,
              height: 56,
              child: Tooltip(
                message: tip,
                child: Icon(icon, color: Colors.white, size: 30),
              ),
            ),
          ),
        );
    final Widget? center;
    if (ring != null) {
      center = ring;
    } else if (hasLocal) {
      // Own / saved photo being opened: normally a blink. Offer a retry
      // only if opening failed twice.
      center = _prepareFailures >= 2
          ? button(Icons.refresh_rounded, 'Try again', _openOrRetryLocal,
              const Key('chat_photo_prepare'))
          : null;
    } else {
      center = button(Icons.download_rounded, 'Download', _download,
          const Key('chat_photo_download'));
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          key: const Key('chat_photo_placeholder'),
          width: frame.width,
          height: frame.height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Color(0xFF2A2F3A)),
              if (center == null)
                Center(
                  child: Icon(Icons.image_rounded,
                      color: Colors.white.withValues(alpha: .25), size: 34),
                )
              else
                Center(
                  child: FittedBox(fit: BoxFit.scaleDown, child: center),
                ),
              if (ring == null)
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: VideoChip(label: _sizeLabel(a.size)),
                ),
              if (!running && progress?.error != null)
                Positioned(
                  left: 8,
                  right: 8,
                  top: 8,
                  child: Text(
                    progress!.error!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 11.5),
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

/// Bundle 150: blue ring fed by live Wi-Fi progress for [messageId]. Turns
/// (no %) until the first number arrives, then fills to 100%.
class _LiveRing extends StatelessWidget {
  const _LiveRing({
    super.key,
    required this.messageId,
    required this.sizeBytes,
    required this.icon,
    required this.idleLabel,
  });

  final String messageId;
  final int sizeBytes;
  final IconData icon;
  final String idleLabel;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MediaProgress?>(
      valueListenable: MediaProgressHub.instance.watch(messageId),
      builder: (context, p, _) {
        if (p == null) return BlueProgressRing(icon: icon, label: idleLabel);
        // Sender reports chunks, receiver bytes: show MB from the real size.
        final total = sizeBytes > 0 ? sizeBytes : p.total;
        final done = sizeBytes > 0 ? (p.fraction * sizeBytes).round() : p.done;
        return BlueProgressRing(
          fraction: p.fraction,
          icon: icon,
          label: mediaProgressLabel(done, total),
        );
      },
    );
  }
}
