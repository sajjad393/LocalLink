import 'dart:io';

import 'package:flutter/material.dart';

import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/core/widgets/admin_crown.dart';
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

  /// Bundle 214: the account id when [peerId] is a phone id (or for my own
  /// photo), so the admin crown can show.
  final String? userId;

  /// Bundle 214: show the admin crown 👑 (top centre) when this person is
  /// an admin. Off for places that must not show it.
  final bool crown;

  const AccountAvatar({super.key, required this.name, this.localPath = '', this.radius = 28, this.iconSize, this.peerId, this.locked = false, this.userId, this.crown = true});

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

  /// Bundle 207 (O, Option B): a thin blue ring (no white fill) with a
  /// small see-through gap, and a small blue lock badge at the bottom-right
  /// cut out with the page colour. Same outside size as before.
  double get _ring => radius * 0.06 < 2 ? 2 : radius * 0.06;
  double get _gap => radius * 0.05 < 1.5 ? 1.5 : radius * 0.05;
  double get _inner => radius - _ring - _gap;

  /// The colour behind the avatar (the card it sits on, or the page), so
  /// the badge cut-out never shows a fixed white in dark mode.
  static Color pageColorOf(BuildContext context) {
    final page = Theme.of(context).scaffoldBackgroundColor;
    final m = Material.maybeOf(context)?.color;
    if (m == null || m.a == 0) return page;
    return m.a >= 1 ? m : Color.alphaBlend(m, page);
  }

  Widget _circle(BuildContext context, ImageProvider? image) =>
      locked ? _lockedCircle(context, image) : _plainCircle(image, radius);

  Widget _lockedCircle(BuildContext context, ImageProvider? image) {
    final badge = radius * 0.5 < 18 ? 18.0 : radius * 0.5;
    final cut = badge * 0.12 < 2 ? 2.0 : badge * 0.12;
    final page = pageColorOf(context);
    return SizedBox(
      key: const ValueKey('avatar_private_lock'),
      width: radius * 2,
      height: radius * 2,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            key: const ValueKey('avatar_private_ring'),
            width: radius * 2,
            height: radius * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: ringStart, width: _ring),
            ),
            alignment: Alignment.center,
            child: _plainCircle(image, _inner),
          ),
          Positioned(
            right: -cut * 0.5,
            bottom: -cut * 0.5,
            child: Container(
              key: const ValueKey('avatar_private_badge'),
              width: badge,
              height: badge,
              decoration: BoxDecoration(
                color: ringStart,
                shape: BoxShape.circle,
                border: Border.all(color: page, width: cut),
              ),
              alignment: Alignment.center,
              child: Icon(Icons.lock_rounded,
                  size: (badge - cut * 2) * 0.62, color: Colors.white),
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
    final photo = _photo(context);
    if (!crown) return photo;
    return AdminCrown(id: peerId, otherId: userId, radius: radius, child: photo);
  }

  Widget _photo(BuildContext context) {
    final own = _imageFor(localPath);
    final id = peerId ?? '';
    if (own != null || id.isEmpty) return _circle(context, own);
    // Bundle 204: the letter until the picture comes, then the picture
    // (no spinner).
    return ListenableBuilder(
      listenable: PeerPhotoBook.instance,
      builder: (context, _) =>
          _circle(context,
              _imageFor(PeerPhotoBook.instance.fileFor(id)?.path ?? '')),
    );
  }
}
