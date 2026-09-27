import 'dart:io';

import 'package:flutter/material.dart';

class AccountAvatar extends StatelessWidget {
  final String name;
  final String localPath;
  final double radius;
  final double? iconSize;

  const AccountAvatar({super.key, required this.name, this.localPath = '', this.radius = 28, this.iconSize});

  ImageProvider? get _image {
    if (localPath.isEmpty) return null;
    final file = File(localPath);
    if (!file.existsSync()) return null;
    return FileImage(file);
  }

  String get _initial {
    final value = name.trim();
    if (value.isEmpty) return '?';
    return value.substring(0, 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundImage: _image,
      child: _image == null ? Text(_initial, style: TextStyle(fontSize: iconSize ?? radius * 0.72, fontWeight: FontWeight.w700)) : null,
      foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
    );
  }
}
