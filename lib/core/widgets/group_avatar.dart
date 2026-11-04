import 'package:flutter/material.dart';

import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/features/groups/data/group_photo_book.dart';

/// Brand-gradient avatar used for every group surface (home conversation rows,
/// group chat app bar, group details header) so groups read as one visual
/// family next to the vivid [AccountAvatar] palette for people.
///
/// Bundle G2: shows the group photo when [groupId] + [photoVersion] point to
/// a photo on this phone.
class GroupAvatar extends StatelessWidget {
  final double radius;
  final IconData icon;
  final String? groupId;
  final int photoVersion;

  const GroupAvatar({
    super.key,
    this.radius = 24,
    this.icon = Icons.groups_rounded,
    this.groupId,
    this.photoVersion = 0,
  });

  Widget _gradient() => Container(
        width: radius * 2,
        height: radius * 2,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          gradient: LocalLinkBrand.linearGradient,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: radius * 1.05),
      );

  @override
  Widget build(BuildContext context) {
    final id = groupId;
    if (id == null || photoVersion <= 0) return _gradient();
    return ListenableBuilder(
      listenable: GroupPhotoBook.instance,
      builder: (context, _) {
        final file = GroupPhotoBook.instance.fileFor(id, photoVersion);
        if (file == null) return _gradient();
        return ClipOval(
          key: const ValueKey('group_photo'),
          child: Image.file(
            file,
            width: radius * 2,
            height: radius * 2,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _gradient(),
          ),
        );
      },
    );
  }
}
