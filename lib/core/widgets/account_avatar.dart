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

  const AccountAvatar({super.key, required this.name, this.localPath = '', this.radius = 28, this.iconSize, this.peerId});

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

  Widget _circle(ImageProvider? image) => CircleAvatar(
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
