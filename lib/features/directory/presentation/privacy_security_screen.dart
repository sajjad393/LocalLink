import 'package:locallink/core/widgets/link_toast.dart';
import 'package:flutter/material.dart';
import 'package:locallink/core/bloc/bloc_utils.dart';
import 'package:locallink/core/models/profile.dart';
import 'package:locallink/features/account/domain/account_repository_contract.dart';
import 'package:locallink/features/account/bloc/account_bloc.dart';
import 'package:locallink/features/directory/domain/directory_repository_contract.dart';
import 'package:locallink/l10n/l10n.dart';

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
        LinkToast.show(context, saved
                ? L.t.privacySettingsSaved
                : L.t.savedLocallyWillSyncWhenAvailable, kind: LinkToastKind.done);
    } catch (e) {
      if (mounted)
        LinkToast.show(context, cleanBlocError(e), kind: LinkToastKind.error);
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
      appBar: AppBar(title: Text(L.t.privacySecurity)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(L.t.directoryVisibility,
            style: TextStyle(fontWeight: FontWeight.bold)),
        SwitchListTile(
            title: Text(L.t.discoverableByPhone),
            subtitle:
                Text(L.t.allowPeopleToFindYouWith),
            value: byPhone,
            onChanged: (v) => setState(() => byPhone = v)),
        SwitchListTile(
            title: Text(L.t.discoverableByName),
            subtitle: Text(L.t.allowNameSearchesToReturnYour),
            value: byName,
            onChanged: (v) => setState(() => byName = v)),
        SwitchListTile(
            title: Text(L.t.directorySynchronization),
            subtitle: Text(
                L.t.shareYourSignedPublicProfileThrough),
            value: sync,
            onChanged: (v) => setState(() => sync = v)),
        ListTile(
          title: Text(L.t.phoneNumberVisibility),
          trailing: DropdownButton<String>(
              value: visibility,
              items: [
                DropdownMenuItem(value: 'private', child: Text(L.t.nobody)),
                DropdownMenuItem(value: 'contacts', child: Text(L.t.contacts)),
                DropdownMenuItem(value: 'public', child: Text(L.t.everyone))
              ],
              onChanged: (v) {
                if (v != null) setState(() => visibility = v);
              }),
        ),
        const Divider(),
        ListTile(
            leading: Icon(Icons.fingerprint),
            title: Text(L.t.identitySigning),
            subtitle: Text(
                L.t.identityKeysAreManagedLocallyAnd)),
        const SizedBox(height: 12),
        FilledButton(
            onPressed: saving ? null : _save,
            child: saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(L.t.saveChanges))
      ]));
}
