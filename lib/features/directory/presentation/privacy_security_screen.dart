import 'package:flutter/material.dart';
import 'package:locallink/core/models/profile.dart';
import 'package:locallink/features/account/domain/account_repository_contract.dart';
import 'package:locallink/features/account/bloc/account_bloc.dart';
import 'package:locallink/features/directory/domain/directory_repository_contract.dart';

class PrivacySecurityScreen extends StatefulWidget {
  final AccountRepositoryContract accountRepository;
  final DirectoryRepositoryContract? directoryRepository;
  const PrivacySecurityScreen(
      {super.key, required this.accountRepository, this.directoryRepository});
  @override
  State<PrivacySecurityScreen> createState() => _PrivacySecurityScreenState();
}

class _PrivacySecurityScreenState extends State<PrivacySecurityScreen> {
  LocalProfile? p;
  bool byPhone = true, byName = true, sync = true;
  String visibility = 'contacts';
  bool saving = false;
  late final AccountBloc bloc;
  @override
  void initState() {
    super.initState();
    bloc = AccountBloc(widget.accountRepository);
    _load();
  }

  Future<void> _load() async {
    await bloc.load();
    if (!mounted) return;
    final x = bloc.profile;
    if (x != null)
      setState(() {
        p = x;
        byPhone = x.discoverableByPhone;
        byName = x.discoverableByName;
        sync = x.directorySyncEnabled;
        visibility = x.phoneVisibility;
      });
  }

  Future<void> _save() async {
    final x = p;
    if (x == null || saving) return;
    setState(() => saving = true);
    try {
      final saved = await bloc.saveProfile(
          displayName: x.displayName,
          username: x.username,
          phoneNumber: x.phoneNumber,
          phoneVisibility: visibility,
          discoverableByPhone: byPhone,
          discoverableByName: byName,
          directorySyncEnabled: sync);
      await widget.directoryRepository?.publishOwnProfile();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(saved
                ? 'Privacy settings saved'
                : 'Saved locally; will sync when available')));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  void dispose() {
    bloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Privacy & Security')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Directory visibility',
            style: TextStyle(fontWeight: FontWeight.bold)),
        SwitchListTile(
            title: const Text('Discoverable by phone'),
            subtitle:
                const Text('Allow people to find you with your phone number'),
            value: byPhone,
            onChanged: (v) => setState(() => byPhone = v)),
        SwitchListTile(
            title: const Text('Discoverable by name'),
            subtitle: const Text('Allow name searches to return your profile'),
            value: byName,
            onChanged: (v) => setState(() => byName = v)),
        SwitchListTile(
            title: const Text('Directory synchronization'),
            subtitle: const Text(
                'Share your signed public profile through LocalLink'),
            value: sync,
            onChanged: (v) => setState(() => sync = v)),
        ListTile(
          title: const Text('Phone number visibility'),
          trailing: DropdownButton<String>(
              value: visibility,
              items: const [
                DropdownMenuItem(value: 'private', child: Text('Nobody')),
                DropdownMenuItem(value: 'contacts', child: Text('Contacts')),
                DropdownMenuItem(value: 'public', child: Text('Everyone'))
              ],
              onChanged: (v) {
                if (v != null) setState(() => visibility = v);
              }),
        ),
        const Divider(),
        const ListTile(
            leading: Icon(Icons.fingerprint),
            title: Text('Identity & encryption'),
            subtitle: Text(
                'Identity keys are managed locally and are not shown in your public profile.')),
        const SizedBox(height: 12),
        FilledButton(
            onPressed: saving ? null : _save,
            child: saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save changes'))
      ]));
}
