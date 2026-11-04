import 'package:flutter/material.dart';

import 'package:locallink/features/groups/presentation/widgets/group_sheets.dart'
    show GroupSheetAction;

/// Bundle 204 (mock 204 B1): what the Profile photo sheet gave.
enum ProfilePhotoChoice { camera, gallery, remove }

/// Bundle 204 (mock 204 B1): "Profile photo" - Camera / Gallery /
/// Remove photo (red, only when there is a picture).
Future<ProfilePhotoChoice?> showProfilePhotoSheet(BuildContext context,
    {required bool hasPhoto}) {
  return showModalBottomSheet<ProfilePhotoChoice>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    builder: (c) {
      final colors = Theme.of(c).colorScheme;
      return SingleChildScrollView(
        key: const ValueKey('profile_photo_sheet'),
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 0, 2, 6),
              child: Text('Profile photo',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurfaceVariant)),
            ),
            GroupSheetAction(
              key: const ValueKey('profile_photo_camera'),
              icon: Icons.photo_camera_outlined,
              title: 'Camera',
              onTap: () => Navigator.pop(c, ProfilePhotoChoice.camera),
            ),
            GroupSheetAction(
              key: const ValueKey('profile_photo_gallery'),
              icon: Icons.photo_library_outlined,
              title: 'Gallery',
              onTap: () => Navigator.pop(c, ProfilePhotoChoice.gallery),
            ),
            if (hasPhoto)
              GroupSheetAction(
                key: const ValueKey('profile_photo_remove'),
                icon: Icons.delete_outline_rounded,
                title: 'Remove photo',
                red: true,
                onTap: () => Navigator.pop(c, ProfilePhotoChoice.remove),
              ),
          ],
        ),
      );
    },
  );
}
