import 'package:flutter/material.dart';

import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/core/widgets/local_link_button.dart';
import 'package:locallink/core/widgets/local_link_text_field.dart';

class CreateGroupResult {
  final String name;
  final List<String> memberIds;

  const CreateGroupResult({required this.name, required this.memberIds});
}

class CreateGroupDialog extends StatefulWidget {
  final List<Device> devices;

  const CreateGroupDialog({super.key, required this.devices});

  @override
  State<CreateGroupDialog> createState() => _CreateGroupDialogState();
}

class _CreateGroupDialogState extends State<CreateGroupDialog> {
  final _nameController = TextEditingController();
  final _selected = <String>{};

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New group'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LocalLinkTextField(
                controller: _nameController,
                labelText: 'Group name',
              ),
              const SizedBox(height: LocalLinkSpacing.lg),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Members', style: LocalLinkTypography.cardTitle),
              ),
              if (widget.devices.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: LocalLinkSpacing.lg),
                  child: Text('No other registered devices are available.'),
                )
              else
                ...widget.devices.map(
                  (device) => CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _selected.contains(device.id),
                    title: Text(device.name),
                    subtitle: Text(device.platform),
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          _selected.add(device.id);
                        } else {
                          _selected.remove(device.id);
                        }
                      });
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        LocalLinkButton(variant: LocalLinkButtonVariant.text, expanded: false, onPressed: () => Navigator.pop(context), label: 'Cancel'),
        LocalLinkButton(expanded: false,
          onPressed: () {
            final name = _nameController.text.trim();
            if (name.isEmpty) return;
            Navigator.pop(
              context,
              CreateGroupResult(name: name, memberIds: _selected.toList()),
            );
          },
          label: 'Create',
        ),
      ],
    );
  }
}
