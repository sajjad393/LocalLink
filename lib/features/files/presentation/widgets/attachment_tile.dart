import 'dart:async';
import 'dart:io';
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
import 'package:locallink/features/files/data/services/media_transfer_actions.dart';
import 'package:locallink/features/files/data/services/auto_fetch_service.dart';
import 'blue_progress_ring.dart';
import 'chat_photo.dart';
import 'chat_video_controller.dart';
import 'chat_video_player.dart';
import 'media_frame.dart';
import 'media_playback_coordinator.dart';
import 'media_view_cache.dart';
import 'package:locallink/core/services/media_book.dart';
import 'package:locallink/features/storage/data/media_storage_service.dart';
import 'package:locallink/features/storage/presentation/removed_media_view.dart';
import 'package:locallink/features/messaging/data/read_receipts/voice_played_hub.dart';
import 'media_tile_look.dart';
import 'media_grid.dart';
import 'prepare_ring.dart';

class AttachmentTile extends StatefulWidget {
  final Attachment attachment;
  final FileTransferRepositoryContract transfer;
  final String messageId;
  final String? groupMessageId;

  /// Outgoing bubbles show a circular upload ring over the image while the
  /// outbox is still flushing this message (WhatsApp-style affordance).
  final bool uploading;

  /// Bundle 174 (6): my own photo/video was cancelled (or failed): show
  /// "Not sent - tap to retry"; [onRetry] runs on tap.
  final bool failed;
  final VoidCallback? onRetry;

  /// Bundle 182: [uploading] and the friend is Offline. Photos and videos
  /// show a clock + "Waiting" instead of the ring (documents: no change).
  final bool waiting;

  /// Bundle 197b: my own message (removed media: tap restores from my
  /// Gallery) and the sender's name (receiver: "Ask Sajjad to send it
  /// again.").
  final bool mine;
  final String? senderName;

  /// Bundle 198: my own 1-to-1 voice note - false = grey mic (not played
  /// yet), true = blue mic (played). Null = no mic (default).
  final bool? playedMark;

  /// Bundle 202: square in a media grid (photo / video only). The picture
  /// fills the square (cover); null = the normal tile.
  final Size? cell;

  /// Bundle 202: tap on a ready grid square (opens the swipe viewer).
  final VoidCallback? onOpen;

  const AttachmentTile({
    super.key,
    required this.attachment,
    required this.transfer,
    required this.messageId,
    this.groupMessageId,
    this.uploading = false,
    this.failed = false,
    this.onRetry,
    this.waiting = false,
    this.mine = false,
    this.senderName,
    this.playedMark,
    this.cell,
    this.onOpen,
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
  // Bundle 208 (C1): the grid square asked for the video's first frame.
  bool _frameAsked = false;
  // Bundle 208 (D6): my saved file is being opened (ring with %).
  bool _opening = false;
  Timer? _frameRetry;

  @override
  void initState() {
    super.initState();
    _localPath = widget.attachment.localPath;
    _controller = FileTransferBloc(repository: widget.transfer);
    MediaTransferActions.instance.cancelled.addListener(_onCancelledChanged);
    // Bundle 197b: removed to save space - no file to open, no download.
    _media = MediaBook.instance.of(widget.attachment.id);
    MediaBook.instance.addListener(_onMediaBook);
    _auto = AutoFetch.instance;
    _auto?.arrived.addListener(_onAutoFetch);
    if (_removed) return;
    _prepareExistingPath();
    _maybeAutoDownload();
  }

  // Bundle 208 (E6): the background downloader (null in some tests).
  AutoFetch? _auto;

  bool get _autoFetching =>
      _auto?.isFetching(widget.messageId, widget.attachment.id) ?? false;

  /// An online download by [AutoFetch] ended (saved, failed or stopped).
  void _onAutoFetch() {
    if (!mounted) return;
    final path = _auto?.pathFor(widget.attachment.id);
    final local = _localPath;
    if (path != null && path.isNotEmpty && (local == null || local.isEmpty)) {
      AppLogger.info('ATTACHMENT_PATH_ARRIVED',
          detail: 'file=${widget.attachment.id} by=auto');
      _localPath = path;
      _prepareFailures = 0;
      unawaited(_prepareExistingPath());
    }
    setState(() {});
  }

  AutoFile _autoFile() => AutoFile(
        messageId: widget.groupMessageId ?? widget.messageId,
        attachment: widget.attachment,
        senderId: '',
        createdAt: DateTime.now().toUtc(),
        groupId: widget.groupMessageId == null ? null : '',
      );

  Future<void> _stopAuto() async {
    AppLogger.info('MEDIA_CANCEL_RECEIVE',
        detail: 'file=${widget.attachment.id} way=online');
    await _auto?.stop(widget.messageId, widget.attachment.id);
    if (mounted) setState(() {});
  }

  /// Bundle 208 (E6): small ring with X for a voice note / document row.
  Widget _autoMiniRing() => ValueListenableBuilder<MediaProgress?>(
        valueListenable: MediaProgressHub.instance
            .watchFile(widget.messageId, widget.attachment.id),
        builder: (context, p, _) => Stack(
          key: const Key('chat_media_auto_mini_ring'),
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(value: p?.fraction, strokeWidth: 3),
            IconButton(
              tooltip: 'Cancel download',
              onPressed: () => unawaited(_stopAuto()),
              icon: const Icon(Icons.close, size: 18),
            ),
          ],
        ),
      );

  // Bundle 197b: this file's small picture / removed / saved state.
  MediaState? _media;
  bool get _removed => _media?.isRemoved ?? false;

  void _onMediaBook() {
    final next = MediaBook.instance.of(widget.attachment.id);
    if (next == _media || !mounted) return;
    final wasRemoved = _removed;
    _media = next;
    if (!wasRemoved && _removed) {
      // Removed while on screen: drop the view, show the small picture.
      _releaseView();
      setState(() => _displayPath = null);
    } else if (wasRemoved && !_removed) {
      // Copied back from my Gallery: open it as normal.
      _prepareFailures = 0;
      setState(() {});
      unawaited(_prepareExistingPath());
    } else {
      setState(() {});
    }
  }

  void _markOpened() => unawaited(MediaBook.instance.markOpened(widget.attachment.id));

  /// Bundle 197b (T1): first time the plain view exists, make the small
  /// picture (kept when the file is removed later).
  void _ensureThumb(String view) {
    if (_media?.hasThumb ?? false) return;
    if (!widget.attachment.isImage && !_isVideo) return;
    if (!MediaStorageService.instance.configured) return;
    unawaited(MediaStorageService.instance
        .ensureThumb(widget.attachment.id, view, video: _isVideo && !widget.attachment.isImage));
  }

  void _onCancelledChanged() {
    if (mounted) setState(() {});
  }

  /// Bundle 174 (6): a nearby photo/video I was receiving got cancelled.
  bool get _receiveCancelled =>
      _arrivingDirect &&
      MediaTransferActions.instance.isCancelled(widget.messageId);

  /// Bundle 174 (6): sender pressed X and said Yes.
  Future<void> _cancelSend() async {
    final id = widget.attachment.id;
    AppLogger.info('MEDIA_CANCEL_SEND', detail: 'file=$id');
    final action = MediaTransferActions.instance.cancelSend;
    try {
      if (action != null) {
        await action(widget.messageId, id);
      } else {
        await widget.transfer.cancelDirectFile(id);
      }
    } catch (_) {}
    MediaProgressHub.instance.clear(widget.messageId, fileId: id); // Bundle 203 (6)
    if (mounted) setState(() {});
  }

  /// Bundle 174 (6): receiver pressed X and said Yes.
  Future<void> _cancelReceive() async {
    final id = widget.attachment.id;
    AppLogger.info('MEDIA_CANCEL_RECEIVE', detail: 'file=$id');
    // Bundle 208 (E2): I stopped it - never again by itself.
    MediaTransferActions.instance.stopByMe(id);
    MediaTransferActions.instance.markCancelled(widget.messageId);
    final action = MediaTransferActions.instance.cancelReceive;
    try {
      if (action != null) {
        await action(widget.messageId, id);
      } else {
        await widget.transfer.cancelDirectFile(id);
      }
    } catch (_) {}
    MediaProgressHub.instance.clear(widget.messageId, fileId: id); // Bundle 203 (6)
  }

  /// Bundle 174 (6): "Tap to download" after a cancel - ask the sender's
  /// phone to send it again.
  Future<void> _requestResend() async {
    final id = widget.attachment.id;
    AppLogger.info('MEDIA_RESEND_ASK', detail: 'file=$id');
    // Bundle 208 (E2): I want it again - it may come by itself again.
    MediaTransferActions.instance.clearStops(widget.messageId, id);
    MediaTransferActions.instance.clearCancelled(widget.messageId);
    final action = MediaTransferActions.instance.requestResend;
    var ok = false;
    try {
      ok = action != null && await action(widget.messageId, id);
    } catch (_) {}
    if (!ok && mounted) {
      MediaTransferActions.instance.markCancelled(widget.messageId);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
          content: Text('Could not reach the sender. Try again when nearby.')));
    }
  }

  /// Bundle 208 (E7): a stuck Nearby file the phone asks for by itself.
  bool get _waitsForSender =>
      _auto != null &&
      !widget.mine &&
      _auto!.willAsk(widget.messageId, widget.attachment.id);

  Widget _tapToDownload() => _waitsForSender ? _waitingFor() : _tapToDownloadButton();

  /// Bundle 208 (E7): "Waiting for Sajjad" (small grey text); a tap still
  /// asks at once.
  Widget _waitingFor() {
    final name = (widget.senderName ?? '').trim();
    return GestureDetector(
      key: const Key('chat_media_waiting_for'),
      behavior: HitTestBehavior.opaque,
      onTap: () => unawaited(_requestResend()),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const DecoratedBox(
            decoration:
                BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
            child: SizedBox(
              width: 48,
              height: 48,
              child: Icon(Icons.schedule_rounded, color: Colors.white70, size: 26),
            ),
          ),
          const SizedBox(height: 6),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black45,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              child: Text(
                name.isEmpty ? 'Waiting for sender' : 'Waiting for $name',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFFD0D4DC), fontSize: 11.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tapToDownloadButton() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: Colors.black54,
            shape: const CircleBorder(),
            child: InkWell(
              key: const Key('chat_media_tap_to_download'),
              customBorder: const CircleBorder(),
              onTap: () => unawaited(_requestResend()),
              child: const SizedBox(
                width: 56,
                height: 56,
                child: Icon(Icons.download_rounded,
                    color: Colors.white, size: 30),
              ),
            ),
          ),
          const SizedBox(height: 6),
          const VideoChip(label: 'Tap to download'),
        ],
      );

  /// Bundle 174 (6): "Not sent - tap to retry" over my own cancelled media.
  Widget _withFailed(Widget child) {
    if (!widget.failed) return child;
    return Stack(
      children: [
        child,
        Positioned(
          left: 0,
          right: 0,
          top: widget.cell == null ? 18 : 8,
          child: Center(
            child: _fitCell(GestureDetector(
              key: const Key('chat_media_not_sent'),
              behavior: HitTestBehavior.opaque,
              onTap: widget.onRetry,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xDDB3261E),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh_rounded, color: Colors.white, size: 16),
                    SizedBox(width: 4),
                    Text(
                      'Not sent - tap to retry',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            )),
          ),
        ),
      ],
    );
  }

  /// Bundle 202: wide chips shrink to fit a grid square.
  Widget _fitCell(Widget child) => widget.cell == null
      ? child
      : Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: FittedBox(fit: BoxFit.scaleDown, child: child),
        );

  /// Bundle 208 (C1): ask once for the first frame of [path]; redraw when
  /// it comes.
  void _askFrame(String path) {
    if (_frameAsked) return;
    _frameAsked = true;
    final key = _videoCacheKey;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(VideoInfoCache.load(path, key).then((info) {
        if (!mounted) return;
        if (info?.thumbnail != null) {
          setState(() {});
        } else if (info == null) {
          // Bundle 208 (C4): the file may still be being written - once more.
          _frameRetry = Timer(VideoInfoCache.retryGap, () {
            if (!mounted) return;
            unawaited(VideoInfoCache.load(path, key).then((again) {
              if (mounted && again?.thumbnail != null) setState(() {});
            }));
          });
        }
      }));
    });
  }

  /// Bundle 202 (mock A2-A6): a ready photo / video as a grid square -
  /// cover crop, videos get a play button and their length. Tap = viewer.
  Widget _compactReady(String path) {
    final cell = widget.cell!;
    final a = widget.attachment;
    final video = !a.isImage;
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
    final info = video ? VideoInfoCache.peek(_videoCacheKey) : null;
    // Bundle 208 (C1): a grid square never builds a ChatVideoPlayer, so it
    // reads the first frame itself (was: only after the video was played).
    if (video && info == null) _askFrame(path);
    if (info?.thumbnail != null) MediaThumbs.shown(a.id, 'frame', where: 'grid');
    const dark = ColoredBox(color: Color(0xFF2A2F3A));
    final Widget picture;
    if (!video) {
      picture = Image.file(
        File(path),
        key: ValueKey<String>('grid_photo:${a.id}'),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        cacheWidth: (cell.width * dpr).round().clamp(64, 1080),
        errorBuilder: (_, __, ___) => dark,
      );
    } else if (info?.thumbnail != null) {
      picture = Image.memory(info!.thumbnail!,
          key: ValueKey<String>('grid_video:${a.id}'),
          fit: BoxFit.cover,
          gaplessPlayback: true);
    } else {
      picture = MediaThumbFill(
          key: ValueKey<String>('grid_video:${a.id}'),
          attachmentId: a.id,
          fallback: dark);
    }
    final known = info?.durationMs ?? 0;
    final ms = known > 0 ? known : (_media?.mediaMs ?? 0);
    return SizedBox(
      key: ValueKey<String>('grid_cell:${a.id}'),
      width: cell.width,
      height: cell.height,
      child: Stack(fit: StackFit.expand, children: [
        dark,
        picture,
        if (video && !widget.uploading)
          const Center(
            child: DecoratedBox(
              decoration:
                  BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
              child: Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.play_arrow_rounded,
                    color: Colors.white, size: 28),
              ),
            ),
          ),
        if (video && ms > 0)
          Positioned(
            left: 6,
            bottom: 6,
            child: VideoChip(
                icon: Icons.videocam_rounded,
                label: formatVideoClock(Duration(milliseconds: ms))),
          ),
        Positioned.fill(
          child: GestureDetector(
            key: ValueKey<String>('grid_open:${a.id}'),
            behavior: HitTestBehavior.opaque,
            onTap: widget.uploading
                ? null
                : () {
                    _markOpened();
                    widget.onOpen?.call();
                  },
          ),
        ),
        if (widget.uploading) _sendOverlay(),
      ]),
    );
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
        _displayPath == null &&
        !_removed) {
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
    if (widget.uploading) return false;
    // Bundle G7: a member's group file coming Nearby (no server link yet)
    // - same ring / Tap to download as 1:1. My own group files never.
    if (widget.groupMessageId != null && widget.mine) return false;
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
    // Bundle 208 (E6): AutoFetch already gets every file of the last 7
    // days (any type, up to 50 MB) in the background, one at a time. On
    // screen the bubble only asks for its small photo / voice / video (any
    // age, as before) - through the same line, never twice.
    final auto = _auto;
    if (auto != null) {
      if (widget.mine || auto.gaveUp(widget.messageId, widget.attachment.id)) {
        return;
      }
      if (MediaTransferActions.instance.stoppedByMe(widget.attachment.id)) {
        return;
      }
      final small = (widget.attachment.isImage || _isAudio || _isVideo) &&
          widget.attachment.size <= 10 * 1024 * 1024;
      if (!small) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _activeOperation != null) return;
        auto.fetchNow(_autoFile());
        setState(() {});
      });
      return;
    }
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
    if (!_opening) {
      _opening = true;
      // Called from initState / didUpdateWidget too: redraw a moment later.
      scheduleMicrotask(() {
        if (mounted) setState(() {});
      });
    }
    try {
      var localPath = path;
      if (!await widget.transfer.isProtectedLocalFile(localPath)) {
        localPath = await widget.transfer.protectLegacyLocalFile(localPath);
        if (mounted) setState(() => _localPath = localPath);
      }
      final view = await _acquireView(localPath);
      if (view == null) return;
      setState(() => _displayPath = view);
      _ensureThumb(view);
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
    } finally {
      if (mounted && _opening) setState(() => _opening = false);
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
    // Bundle 208 (E6): a tap goes to the front of the background line
    // (never two downloads of the same file).
    final auto = _auto;
    if (auto != null && auto.serverUp()) {
      MediaTransferActions.instance
          .clearStops(widget.messageId, widget.attachment.id);
      auto.fetchNow(_autoFile(), force: true);
      setState(() {});
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
      _ensureThumb(view);
      MediaStorageService.instance.onDownloaded(widget.attachment.size);
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
    _markOpened();
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
        // Bundle 198: a friend's 1-to-1 voice note played -> "played" note
        // (sent once; the service checks the first play).
        if (!widget.mine && widget.groupMessageId == null) {
          VoicePlayedHub.instance.played(widget.messageId);
        }
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
    final shown = _displayPath;
    if (shown != null) MediaGalleryRegistry.drop(widget.attachment.id, shown);
    _releaseView();
    MediaBook.instance.removeListener(_onMediaBook);
    _auto?.arrived.removeListener(_onAutoFetch);
    _frameRetry?.cancel();
    MediaTransferActions.instance.cancelled.removeListener(_onCancelledChanged);
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
          // Bundle 197b: removed to save space.
          if (_removed) {
            return RemovedMediaView(
              key: ValueKey<String>('removed_${widget.attachment.id}'),
              attachment: widget.attachment,
              mine: widget.mine,
              senderName: widget.senderName,
              cell: widget.cell,
            );
          }
          final displayPath = _displayPath;
          final saved = !widget.mine && (_media?.isSaved ?? false);
          if (displayPath != null) {
            // Bundle 202: the swipe viewer opens what the chat already shows.
            final key = _viewKey;
            if (key != null && (widget.attachment.isImage || _isVideo)) {
              MediaGalleryRegistry.put(widget.attachment.id, displayPath, key);
            }
            if (widget.cell != null &&
                (widget.attachment.isImage || _isVideo)) {
              return _withSaved(saved, _withFailed(_compactReady(displayPath)));
            }
            if (widget.attachment.isImage) {
              return _withSaved(saved, _withFailed(ChatPhoto(
                key: ValueKey<String>(displayPath),
                path: displayPath,
                sizeKey: _videoCacheKey,
                hintWidth: widget.attachment.width,
                hintHeight: widget.attachment.height,
                uploading: widget.uploading,
                uploadOverlay: _sendOverlay(),
                title: widget.attachment.originalName,
                onOpened: _markOpened,
              )));
            }
            if (_isVideo) {
              // Bundle 145: inline player (same for sender and receiver).
              final viewKey = _viewKey;
              return _withSaved(saved, _withFailed(ChatVideoPlayer(
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
                    : () {
                        _markOpened(); // Bundle 197b: played = opened
                        MediaViewCache.instance.retain(viewKey);
                      },
                onReleaseFile: viewKey == null
                    ? null
                    : (_) => MediaViewCache.instance.release(viewKey),
              )));
            }
          }

          final progress = _progress;
          final running = progress?.status == FileTransferStatus.running;
          if (_isVideo) {
            return _withFailed(_videoPlaceholder(progress, running));
          }
          // Bundle 150: photos never fall back to the grey file row.
          if (widget.attachment.isImage) {
            return _withFailed(_photoPlaceholder(progress, running));
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
                    child: !running && _autoFetching
                        ? _autoMiniRing()
                        : running
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
                                            .withValues(alpha: .35),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              label,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: colors.onSurfaceVariant),
                            ),
                            // Bundle 198: grey / blue mic (played).
                            if (widget.playedMark != null) ...[
                              const SizedBox(width: 4),
                              Icon(
                                Icons.mic_rounded,
                                key: ValueKey(widget.playedMark!
                                    ? 'voice_played_mark'
                                    : 'voice_unplayed_mark'),
                                size: 13,
                                color: widget.playedMark!
                                    ? colors.primary
                                    : colors.onSurfaceVariant,
                              ),
                            ],
                          ],
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
                      Text(
                          saved
                              ? '${_sizeLabel(widget.attachment.size)} · Saved'
                              : _sizeLabel(widget.attachment.size),
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
                else if (_autoFetching)
                  SizedBox(width: 44, height: 44, child: _autoMiniRing())
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

  /// Bundle 208 (D6): files up to this size open too fast for a ring.
  static const int ringMinBytes = 2 * 1024 * 1024;

  /// Bundle 145: video not viewable yet. Arriving: dimmed thumbnail (or
  /// grey), progress ring with X, "4.1 / 11.8 MB". Bigger than 10 MB:
  /// download button. Own file being prepared: play button.
  Widget _videoPlaceholder(TransferProgress? progress, bool running) {
    final cached = VideoInfoCache.peek(_videoCacheKey);
    final a = widget.attachment;
    final hint = a.width > 0 && a.height > 0 ? a.width / a.height : null;
    final size =
        widget.cell ?? ChatVideoPlayer.frameSize(cached?.aspectRatio ?? hint);
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
    } else if (_receiveCancelled) {
      center = FittedBox(fit: BoxFit.scaleDown, child: _tapToDownload());
    } else if (hasLocal &&
        _opening &&
        !widget.uploading &&
        a.size > ringMinBytes) {
      // Bundle 208 (D6): a big saved video being opened - the same "45%"
      // ring as the viewer (small files are too quick to see it).
      center = PrepareRing(
          path: _localPath!,
          size: 56,
          ringKey: const Key('chat_video_prepare_ring'),
          pctKey: const Key('chat_video_prepare_pct'));
    } else if (hasLocal || widget.uploading) {
      center = circle(Icons.play_arrow_rounded, 'Play', _openOrRetryLocal,
          const Key('chat_video_prepare'));
    } else {
      center = circle(Icons.download_rounded, 'Download', _download,
          const Key('chat_video_download'));
    }
    final thumb = cached?.thumbnail;
    // Bundle 150: the ring's own label shows "% · MB" while it runs.
    final sizeChip = ring == null &&
            !(widget.cell != null && cached != null && cached.durationMs > 0)
        ? _sizeLabel(a.size)
        : null;
    return Padding(
      padding: EdgeInsets.only(top: MediaTileLook.topOf(context)),
      child: ClipRRect(
        borderRadius: MediaTileLook.radiusOf(context),
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
              else ...[
                ColoredBox(
                  color: const Color(0xFF2A2F3A),
                  child: Align(
                    alignment: const Alignment(0, -.6),
                    child: Icon(Icons.videocam_rounded,
                        color: Colors.white.withValues(alpha: .25), size: 30),
                  ),
                ),
                // Bundle 208 (C3): the saved small picture while the file
                // is still being locked / opened (was only the plain box).
                Opacity(
                  opacity: .55,
                  child: MediaThumbFill(
                    key: ValueKey<String>('video_wait_thumb:${a.id}'),
                    attachmentId: a.id,
                    fallback: const SizedBox.shrink(),
                  ),
                ),
              ],
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
                  top: MediaTileLook.freeCornerOf(context) ? 8 : null,
                  bottom: MediaTileLook.freeCornerOf(context) ? null : 8,
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
    if (widget.uploading && widget.waiting) {
      return MediaWaitingBadge(
        key: const Key('chat_media_waiting'),
        isVideo: _isVideo,
        onCancel: _cancelSend,
      );
    }
    // Bundle 174 (6): one circle with only the percent, for sending and
    // receiving; tap -> X -> "Cancel this video?".
    if (running) {
      final known = progress != null && progress.total > 0;
      return TransferPercentRing(
        key: const Key('chat_media_download_ring'),
        fraction: known ? progress.fraction : null,
        isVideo: _isVideo,
        onCancel: _cancel,
      );
    }
    // Bundle 208 (E6): downloading online in the background.
    if (_autoFetching) {
      final file = widget.attachment.id;
      return _LiveRing(
        key: const Key('chat_media_auto_ring'),
        messageId: widget.messageId,
        fileId: file,
        sizeBytes: size,
        isVideo: _isVideo,
        onCancel: _stopAuto,
      );
    }
    if (_arrivingDirect && !_receiveCancelled) {
      return _LiveRing(
        key: const Key('chat_media_receiving'),
        messageId: widget.messageId,
        fileId: widget.attachment.id, // Bundle 203 (6)
        sizeBytes: size,
        isVideo: _isVideo,
        onCancel: _cancelReceive,
      );
    }
    if (widget.uploading) {
      return _LiveRing(
        key: const Key('chat_media_sending'),
        messageId: widget.messageId,
        fileId: widget.attachment.id, // Bundle 203 (6)
        sizeBytes: size,
        isVideo: _isVideo,
        onCancel: _cancelSend,
      );
    }
    return null;
  }

  /// Bundle 150: drawn over the sender's own photo/video while it is sent.
  Widget _sendOverlay() => ColoredBox(
        color: Colors.black38,
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: widget.waiting
                ? MediaWaitingBadge(
                    key: const Key('chat_media_waiting'),
                    isVideo: _isVideo,
                    onCancel: _cancelSend,
                  )
                : _LiveRing(
                    key: const Key('chat_media_sending'),
                    messageId: widget.messageId,
                    fileId: widget.attachment.id, // Bundle 203 (6)
                    sizeBytes: widget.attachment.size,
                    isVideo: _isVideo,
                    onCancel: _cancelSend,
                  ),
          ),
        ),
      );

  /// Bundle 150: photo not viewable yet. Same frame as the photo (real
  /// shape when known), blue ring while it moves, never the grey file row.
  /// Bundle 197b (P3): "✓ Saved" bottom-left of a photo / video.
  Widget _withSaved(bool saved, Widget child) {
    if (!saved) return child;
    return Stack(children: [
      child,
      const Positioned(left: 8, bottom: 8, child: IgnorePointer(child: SavedMark())),
    ]);
  }

  Widget _photoPlaceholder(TransferProgress? progress, bool running) {
    final a = widget.attachment;
    final known = MediaSizeCache.get(_videoCacheKey);
    final frame = widget.cell ??
        (known != null
            ? MediaFrame.fit(known.width, known.height)
            : MediaFrame.fit(a.width, a.height));
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
    } else if (_receiveCancelled) {
      center = _tapToDownload();
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
      padding: EdgeInsets.only(top: MediaTileLook.topOf(context)),
      child: ClipRRect(
        borderRadius: MediaTileLook.radiusOf(context),
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
                  top: MediaTileLook.freeCornerOf(context) ? 8 : null,
                  bottom: MediaTileLook.freeCornerOf(context) ? null : 8,
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
/// Bundle 174 (6): only the percent; tap -> X -> confirm -> [onCancel].
class _LiveRing extends StatelessWidget {
  const _LiveRing({
    super.key,
    required this.messageId,
    required this.sizeBytes,
    required this.isVideo,
    this.onCancel,
    this.fileId,
  });

  final String messageId;

  /// Bundle 203 (6): this file's own ring (null = the message ring).
  final String? fileId;
  final int sizeBytes;
  final bool isVideo;
  final Future<void> Function()? onCancel;

  @override
  Widget build(BuildContext context) {
    final hub = MediaProgressHub.instance;
    final file = fileId;
    if (file == null || file.isEmpty) {
      return ValueListenableBuilder<MediaProgress?>(
          valueListenable: hub.watch(messageId),
          builder: (context, p, _) => _ringFor(p));
    }
    // Bundle 203 (6): the file's own number; the message number only while
    // no file of this message has its own (older phones).
    return ValueListenableBuilder<MediaProgress?>(
      valueListenable: hub.watch(messageId),
      builder: (context, m, _) => ValueListenableBuilder<MediaProgress?>(
        valueListenable: hub.watchFile(messageId, file),
        builder: (context, f, _) =>
            _ringFor(f ?? (hub.hasFileProgress(messageId) ? null : m)),
      ),
    );
  }

  Widget _ringFor(MediaProgress? p) {
    return Builder(
      builder: (context) {
        final ring = TransferPercentRing(
          fraction: p?.fraction,
          isVideo: isVideo,
          onCancel: onCancel,
          paused: p?.paused ?? false,
        );
        if (p?.paused != true) return ring;
        // Bundle 179 (1.6): approved mock - pause sign + "Sends after the call".
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ring,
            const SizedBox(height: 6),
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                child: Text(
                  'Sends after the call',
                  key: Key('transfer_paused_label'),
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
