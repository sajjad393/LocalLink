import 'dart:io';

import 'package:flutter/material.dart';

import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/features/directory/data/peer_photo_book.dart';

class AccountAvatar extends StatelessWidget {
  final String name;
  final String localPath;
  final double radius;
  final double? iconSize;

  /// Bundle 204: a friend's user id or phone id. When set (and [localPath]
  /// is empty), the friend's picture from [PeerPhotoBook] shows; else the
  /// letter. Not friends never have a picture there.
  final String? peerId;

  /// Bundle 203 (5b): MY picture while my profile is Private - blue ring on
  /// the edge + a small white circle with a blue lock at the top right.
  /// Owner only (Profile + the Settings card). Same outside size.
  final bool locked;

  const AccountAvatar({super.key, required this.name, this.localPath = '', this.radius = 28, this.iconSize, this.peerId, this.locked = false});

  static const Color ringStart = Color(0xFF1E5BFF);
  static const Color ringEnd = Color(0xFF23E0D8);

  ImageProvider? _imageFor(String path) {
    if (path.isEmpty) return null;
    final file = File(path);
    if (!file.existsSync()) return null;
    return FileImage(file);
  }

  String get _initial {
    final value = name.trim();
    if (value.isEmpty) return '?';
    return value.substring(0, 1).toUpperCase();
  }

  double get _ring => radius * 0.09 < 2.5 ? 2.5 : radius * 0.09;
  double get _inner => locked ? radius - _ring - _ring * 0.8 : radius;

  Widget _circle(ImageProvider? image) => locked ? _lockedCircle(image) : _plainCircle(image, radius);

  Widget _lockedCircle(ImageProvider? image) {
    final badge = radius * 0.62 < 16 ? 16.0 : radius * 0.62;
    return SizedBox(
      key: const ValueKey('avatar_private_lock'),
      width: radius * 2,
      height: radius * 2,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            width: radius * 2,
            height: radius * 2,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [ringStart, ringEnd],
              ),
            ),
            padding: EdgeInsets.all(_ring),
            child: Container(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
              alignment: Alignment.center,
              child: _plainCircle(image, _inner),
            ),
          ),
          Positioned(
            top: radius * 0.02 - badge * 0.15,
            right: radius * 0.02 - badge * 0.15,
            child: Container(
              width: badge,
              height: badge,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 3, offset: const Offset(0, 1)),
                ],
              ),
              alignment: Alignment.center,
              child: Icon(Icons.lock_rounded, size: badge * 0.62, color: ringStart),
            ),
          ),
        ],
      ),
    );
  }

  Widget _plainCircle(ImageProvider? image, double radius) => CircleAvatar(
        radius: radius,
        backgroundImage: image,
        backgroundColor: LocalLinkAvatarColor.forName(name),
        child: image == null ? Text(_initial, style: TextStyle(color: Colors.white, fontSize: iconSize ?? radius * 0.72, fontWeight: FontWeight.w700)) : null,
      );

  @override
  Widget build(BuildContext context) {
    final own = _imageFor(localPath);
    final id = peerId ?? '';
    if (own != null || id.isEmpty) return _circle(own);
    // Bundle 204: the letter until the picture comes, then the picture
    // (no spinner).
    return ListenableBuilder(
      listenable: PeerPhotoBook.instance,
      builder: (context, _) =>
          _circle(_imageFor(PeerPhotoBook.instance.fileFor(id)?.path ?? '')),
    );
  }
}
