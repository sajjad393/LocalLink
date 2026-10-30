import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'media_frame.dart';

/// Bundle 147: photo inside a chat bubble.
///
/// * Real shape: the bubble takes the photo's own width/height ratio, only
///   scaled down to fit 250 x 360 — never cropped or stretched. The sender
///   never stored the size, so it is read from the decoded image (EXIF
///   rotation is applied by the decoder) and remembered for this app run.
/// * Decoded at bubble size (not the full 12 MP camera size).
/// * Tap opens [ChatPhotoViewer] (full screen, pinch to zoom).
class ChatPhoto extends StatefulWidget {
  const ChatPhoto({
    super.key,
    required this.path,
    required this.sizeKey,
    this.hintWidth = 0,
    this.hintHeight = 0,
    this.uploading = false,
    this.title,
    this.uploadOverlay,
  });

  final String path;
  final String sizeKey;
  final int hintWidth;
  final int hintHeight;
  final bool uploading;
  final String? title;

  /// Bundle 150: drawn while [uploading] (blue ring with %). Null = default.
  final Widget? uploadOverlay;

  @override
  State<ChatPhoto> createState() => _ChatPhotoState();
}

class _ChatPhotoState extends State<ChatPhoto> {
  Size? _real;
  ImageProvider? _provider;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void initState() {
    super.initState();
    _real = MediaSizeCache.get(widget.sizeKey) ??
        (widget.hintWidth > 0 && widget.hintHeight > 0
            ? Size(widget.hintWidth.toDouble(), widget.hintHeight.toDouble())
            : null);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(ChatPhoto old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) {
      _provider = null;
      _resolve();
    }
  }

  ImageProvider _buildProvider(BuildContext context) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
    return ResizeImage(
      FileImage(File(widget.path)),
      width: (MediaFrame.maxWidth * dpr).round(),
      height: (MediaFrame.maxHeight * dpr).round(),
      policy: ResizeImagePolicy.fit,
      allowUpscaling: false,
    );
  }

  void _resolve() {
    final provider = _provider ??= _buildProvider(context);
    final stream = provider.resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;
    _stopListening();
    _stream = stream;
    _listener = ImageStreamListener((info, _) {
      final size = Size(info.image.width.toDouble(), info.image.height.toDouble());
      info.dispose();
      MediaSizeCache.put(widget.sizeKey, size);
      final old = _real;
      if (mounted &&
          (old == null || (old.aspectRatio - size.aspectRatio).abs() > 0.01)) {
        setState(() => _real = size);
      }
    }, onError: (_, __) {});
    stream.addListener(_listener!);
  }

  void _stopListening() {
    final l = _listener;
    if (l != null) _stream?.removeListener(l);
    _listener = null;
  }

  @override
  void dispose() {
    _stopListening();
    super.dispose();
  }

  void _open() {
    Navigator.of(context).push(PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, __, ___) =>
          ChatPhotoViewer(path: widget.path, title: widget.title),
      transitionsBuilder: (_, a, __, child) =>
          FadeTransition(opacity: a, child: child),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final real = _real;
    final frame = real == null
        ? MediaFrame.unknown
        : MediaFrame.fit(real.width, real.height);
    final provider = _provider ??= _buildProvider(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          key: const Key('chat_photo_frame'),
          duration: const Duration(milliseconds: 150),
          width: frame.width,
          height: frame.height,
          color: const Color(0xFF2A2F3A),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // contain == the frame already has the photo's ratio, so there
              // are no bars and nothing is cut off.
              Image(
                image: provider,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(Icons.broken_image_outlined,
                      color: Colors.white54, size: 32),
                ),
              ),
              Positioned.fill(
                child: GestureDetector(
                  key: const Key('chat_photo_tap'),
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.uploading ? null : _open,
                ),
              ),
              if (widget.uploading)
                widget.uploadOverlay ?? const _PhotoUploadOverlay(),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoUploadOverlay extends StatelessWidget {
  const _PhotoUploadOverlay();

  @override
  Widget build(BuildContext context) {
    // Indeterminate: the outbox flush doesn't expose a per-byte upload
    // stream; the ring still signals "sending" truthfully.
    return const ColoredBox(
      color: Colors.black38,
      child: Center(
        child: SizedBox(
          width: 72,
          height: 72,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: null,
                strokeWidth: 4,
                color: Colors.white,
                backgroundColor: Colors.white30,
              ),
              Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 28),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bundle 147: full-screen photo. Black background, the whole photo
/// (contain), pinch to zoom up to 5x, double-tap to zoom, swipe down or Back
/// to close. Tap shows/hides the top bar.
class ChatPhotoViewer extends StatefulWidget {
  const ChatPhotoViewer({super.key, required this.path, this.title});

  final String path;
  final String? title;

  @override
  State<ChatPhotoViewer> createState() => _ChatPhotoViewerState();
}

class _ChatPhotoViewerState extends State<ChatPhotoViewer> {
  final _transform = TransformationController();
  bool _barVisible = true;
  TapDownDetails? _doubleTapAt;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky)
        .catchError((Object _) {});
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
            overlays: SystemUiOverlay.values)
        .catchError((Object _) {});
    _transform.dispose();
    super.dispose();
  }

  double get _scale => _transform.value.getMaxScaleOnAxis();

  void _onDoubleTap() {
    if (_scale > 1.01) {
      _transform.value = Matrix4.identity();
      return;
    }
    final p = _doubleTapAt?.localPosition ?? Offset.zero;
    const s = 2.5;
    _transform.value = Matrix4.diagonal3Values(s, s, 1)
      ..setTranslationRaw(-p.dx * (s - 1), -p.dy * (s - 1), 0);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final longest = math.max(mq.size.width, mq.size.height) * mq.devicePixelRatio;
    final provider = ResizeImage(
      FileImage(File(widget.path)),
      width: (longest * 2).round(),
      height: (longest * 2).round(),
      policy: ResizeImagePolicy.fit,
      allowUpscaling: false,
    );
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            onTap: () => setState(() => _barVisible = !_barVisible),
            onDoubleTapDown: (d) => _doubleTapAt = d,
            onDoubleTap: _onDoubleTap,
            child: InteractiveViewer(
              key: const Key('chat_photo_viewer'),
              transformationController: _transform,
              minScale: 1,
              maxScale: 5,
              onInteractionEnd: (details) {
                // Swipe down (not zoomed) closes, like WhatsApp.
                if (_scale <= 1.01 &&
                    details.velocity.pixelsPerSecond.dy > 700) {
                  Navigator.of(context).maybePop();
                }
              },
              child: Center(
                child: Image(
                  image: provider,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white54,
                      size: 48),
                ),
              ),
            ),
          ),
          AnimatedOpacity(
            opacity: _barVisible ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            child: IgnorePointer(
              ignoring: !_barVisible,
              child: SafeArea(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Row(
                    children: [
                      IconButton(
                        key: const Key('chat_photo_viewer_close'),
                        tooltip: 'Back',
                        icon: const Icon(Icons.arrow_back_rounded,
                            color: Colors.white),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                      if (widget.title != null)
                        Expanded(
                          child: Text(widget.title!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 15)),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
