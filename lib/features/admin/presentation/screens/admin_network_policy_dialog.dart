import 'package:flutter/material.dart';

class AdminNetworkPolicyDialog extends StatefulWidget {
  final String title;
  final Map<String, dynamic> policy;
  final bool readOnly;
  final Future<Map<String, dynamic>?> Function(String?)? onSave;
  const AdminNetworkPolicyDialog(
      {super.key,
      required this.title,
      required this.policy,
      required this.readOnly,
      this.onSave});

  static Future<void> show(
      {required BuildContext context,
      required String title,
      required Map<String, dynamic> policy,
      required bool readOnly,
      Future<Map<String, dynamic>?> Function(String?)? onSave}) async {
    await showDialog<void>(
        context: context,
        builder: (_) => AdminNetworkPolicyDialog(
            title: title, policy: policy, readOnly: readOnly, onSave: onSave));
  }

  @override
  State<AdminNetworkPolicyDialog> createState() =>
      _AdminNetworkPolicyDialogState();
}

class _AdminNetworkPolicyDialogState extends State<AdminNetworkPolicyDialog> {
  late String? _wifi;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _wifi =
        widget.policy['wifi_radio_policy']?.toString().trim().isEmpty == true
            ? null
            : widget.policy['wifi_radio_policy']?.toString();
  }

  Future<void> _save() async {
    if (widget.onSave == null) return;
    setState(() => _saving = true);
    final result = await widget.onSave!(_wifi);
    if (!mounted) return;
    setState(() => _saving = false);
    if (result != null) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
          child: SizedBox(
              width: 440,
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                        'LocalLink call and routing transport is local-only: LAN, Wi-Fi Direct and multi-hop mesh.',
                        style: TextStyle(fontSize: 12)),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String?>(
                        value: _wifi,
                        decoration: const InputDecoration(
                            labelText: 'Wi-Fi radio policy'),
                        items: const [
                          DropdownMenuItem<String?>(
                              value: null,
                              child: Text('Inherit / platform state')),
                          DropdownMenuItem<String?>(
                              value: 'allowed', child: Text('Allowed')),
                          DropdownMenuItem<String?>(
                              value: 'forced_on', child: Text('Forced ON')),
                          DropdownMenuItem<String?>(
                              value: 'forced_off', child: Text('Forced OFF')),
                        ],
                        onChanged: widget.readOnly
                            ? null
                            : (v) => setState(() => _wifi = v)),
                    Text(
                        'Effective: ${widget.policy['wifi_radio_policy'] ?? 'allowed'}',
                        style: Theme.of(context).textTheme.bodySmall),
                    if (widget.policy['updated_at'] != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                              'Last policy update: ${widget.policy['updated_at']}')),
                  ]))),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Close')),
        if (!widget.readOnly)
          FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save'))
      ],
    );
  }
}
