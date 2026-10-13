import 'package:flutter/material.dart';

import 'package:locallink/core/theme/app_tokens.dart';

/// Brand-gradient avatar used for every group surface (home conversation rows,
/// group chat app bar, group details header) so groups read as one visual
/// family next to the vivid [AccountAvatar] palette for people.
class GroupAvatar extends StatelessWidget {
  final double radius;
  final IconData icon;

  const GroupAvatar({super.key, this.radius = 24, this.icon = Icons.groups_rounded});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: radius * 2,
      height: radius * 2,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        gradient: LocalLinkBrand.linearGradient,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: Colors.white, size: radius * 1.05),
    );
  }
}
