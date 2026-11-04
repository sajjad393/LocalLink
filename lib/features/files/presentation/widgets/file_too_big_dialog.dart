import 'package:flutter/material.dart';

import '../../domain/file_size_rule.dart';

/// Bundle 203 (5): one file row in the pop-up (name + size).
class TooBigFile {
  const TooBigFile(this.name, this.size, {this.isVideo = false});
  final String name;
  final int size;
  final bool isVideo;
}

/// Bundle 203 (5): "File too big" pop-up (mock 203 F1/F3/F4/F5).
Future<void> showFileTooBigDialog(
  BuildContext context,
  List<TooBigFile> files, {
  bool forward = false,
  bool othersSent = true,
}) {
  if (files.isEmpty) return Future<void>.value();
  final count = files.length;
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      key: const ValueKey('file-too-big-dialog'),
      title: Row(children: [
        const Icon(Icons.warning_amber_rounded, color: Color(0xFFB3261E), size: 22),
        const SizedBox(width: 8),
        Expanded(child: Text(FileSizeRule.title(count))),
      ]),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(FileSizeRule.body(count, forward: forward, othersSent: othersSent)),
          const SizedBox(height: 12),
          for (final f in files.take(5))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Icon(
                    f.isVideo
                        ? Icons.videocam_outlined
                        : Icons.insert_drive_file_outlined,
                    size: 20,
                    color: const Color(0xFF44454C)),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(f.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 8),
                Text(FileSizeRule.sizeLabel(f.size),
                    style: const TextStyle(color: Color(0xFF6A6B73))),
              ]),
            ),
          if (files.length > 5)
            Text('+${files.length - 5} more',
                style: const TextStyle(color: Color(0xFF6A6B73))),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
