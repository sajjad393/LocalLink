import 'package:locallink/core/widgets/link_toast.dart';
import 'package:flutter/material.dart';

import 'package:locallink/features/storage/data/media_storage_service.dart';

/// Bundle 197b (Q4): Admin panel › "Test clean-up now". One run with every
/// file treated as 11 days old and the phone as 80% full. Unsent /
/// undelivered media and voice notes still stay; the switch OFF still wins.
class StorageTestButton extends StatefulWidget {
  const StorageTestButton({super.key, this.service});
  final MediaStorageService? service;

  @override
  State<StorageTestButton> createState() => _StorageTestButtonState();
}

class _StorageTestButtonState extends State<StorageTestButton> {
  bool _running = false;

  MediaStorageService get _service => widget.service ?? MediaStorageService.instance;

  Future<void> _run() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _running = true);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Test clean-up now?'),
        content: const Text(
            'Removes photos, videos and documents as if they were 11 days old and the phone 80% full. Voice notes and unsent media stay. The messages stay with a small picture.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Run test')),
        ],
      ),
    );
    if (ok != true) {
      if (mounted) setState(() => _running = false);
      return;
    }
    final removed = await _service.runAutoClean(trigger: 'test', test: true);
    if (!mounted) return;
    setState(() => _running = false);
    LinkToast.maybeOn(messenger, !_service.autoClean
            ? 'Free up space automatically is OFF. Nothing removed.'
            : 'Test clean-up: $removed ${removed == 1 ? 'file' : 'files'} removed', kind: LinkToastKind.done);
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      key: const Key('admin_storage_test'),
      onPressed: _running ? null : _run,
      icon: _running
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.cleaning_services_outlined),
      label: const Text('Test clean-up now'),
    );
  }
}
