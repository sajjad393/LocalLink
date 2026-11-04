import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:locallink/core/bloc/bloc_utils.dart';
import 'package:locallink/core/models/profile.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/features/account/bloc/account_bloc.dart';
import 'package:locallink/features/account/domain/account_repository_contract.dart';
import 'package:locallink/features/directory/domain/directory_repository_contract.dart';
import 'package:locallink/features/directory/presentation/contact_sheets.dart';

/// Bundle 202 (mock page 5): ONE switch decides both name search and who
/// gets my phone number.
///
/// Private OFF = anyone can find me by name and gets my number (strangers
/// still see it masked). Private ON = no name search, only friends get it.
abstract final class ProfilePrivacyRule {
  static String phoneVisibilityFor({required bool private}) =>
      private ? 'contacts' : 'public';

  static bool isPrivate(LocalProfile? p) => p != null && !p.discoverableByName;

  /// Bundle 203 (5b): my own Private switch, for the lock ring on my picture
  /// (Profile + the Settings card). Null = not read yet.
  static final ValueNotifier<bool?> ownPrivate = ValueNotifier<bool?>(null);

  /// True when the saved phone choice already follows the switch.
  static bool matches(LocalProfile p) =>
      p.phoneVisibility == phoneVisibilityFor(private: isPrivate(p));

  static const String offText =
      'Anyone can find you by name and see your phone number.';
  static const String onText =
      'Nobody can find you by name search. Only friends get your phone number.';
}

/// Bundle 202 (P4): one time after the update, saved profiles whose phone
/// choice does not follow the Private switch are fixed and published again.
abstract final class PhoneVisibilityAlign {
  static const String doneKey = 'phone_vis_align_202';

  static Future<void> runOnce({
    required AccountRepositoryContract account,
    DirectoryRepositoryContract? directory,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(doneKey) == true) return;
      final p = await account.cachedProfile();
      if (p == null) return; // no profile yet - try again next start
      if (ProfilePrivacyRule.matches(p)) {
        await prefs.setBool(doneKey, true);
        return;
      }
      final private = ProfilePrivacyRule.isPrivate(p);
      final to = ProfilePrivacyRule.phoneVisibilityFor(private: private);
      await account.saveProfile(
        displayName: p.displayName,
        username: p.username,
        phoneNumber: p.phoneNumber,
        phoneVisibility: to,
        discoverableByPhone: p.discoverableByPhone,
        discoverableByName: p.discoverableByName,
        directorySyncEnabled: p.directorySyncEnabled,
      );
      await directory?.publishOwnProfile();
      await prefs.setBool(doneKey, true);
      AppLogger.info('PHONE_VIS_ALIGN',
          detail: 'from=${p.phoneVisibility.isEmpty ? 'none' : p.phoneVisibility} '
              'to=$to private=${private ? 'y' : 'n'}');
    } catch (e) {
      AppLogger.info('PHONE_VIS_ALIGN', detail: 'skipped err=${e.runtimeType}');
    }
  }
}

/// Bundle 202 (mock P2/P3): Profile > Privacy > "Private profile" switch
/// (moved here from Settings). Saves at once; turning ON asks first.
class PrivateProfileCard extends StatefulWidget {
  const PrivateProfileCard({
    super.key,
    required this.accountRepository,
    required this.directoryRepository,
    this.onChanged,
  });

  final AccountRepositoryContract accountRepository;
  final DirectoryRepositoryContract? directoryRepository;

  /// The saved profile after a change (Profile keeps "Save changes" in step).
  final ValueChanged<LocalProfile>? onChanged;

  @override
  State<PrivateProfileCard> createState() => _PrivateProfileCardState();
}

class _PrivateProfileCardState extends State<PrivateProfileCard> {
  late final AccountBloc _bloc = AccountBloc(widget.accountRepository);
  bool _loaded = false;
  bool _saving = false;
  bool _private = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _bloc.load();
    if (!mounted) return;
    final p = _bloc.profile;
    setState(() {
      _loaded = p != null;
      _private = ProfilePrivacyRule.isPrivate(p);
    });
    if (p != null) ProfilePrivacyRule.ownPrivate.value = _private;
  }

  @override
  void dispose() {
    _bloc.close();
    super.dispose();
  }

  Future<void> _change(bool makePrivate) async {
    final p = _bloc.profile;
    if (p == null || _saving) return;
    if (makePrivate) {
      final ok = await showPrivateProfileSheet(context);
      if (!ok || !mounted) return;
    }
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _saving = true;
      _private = makePrivate;
    });
    ProfilePrivacyRule.ownPrivate.value = makePrivate; // Bundle 203 (5b): at once
    try {
      final synced = await _bloc.saveProfile(
        displayName: p.displayName,
        username: p.username,
        phoneNumber: p.phoneNumber,
        phoneVisibility:
            ProfilePrivacyRule.phoneVisibilityFor(private: makePrivate),
        discoverableByPhone: p.discoverableByPhone,
        discoverableByName: !makePrivate,
        directorySyncEnabled: p.directorySyncEnabled,
      );
      await widget.directoryRepository?.publishOwnProfile();
      final saved = _bloc.profile;
      if (saved != null) widget.onChanged?.call(saved);
      AppLogger.info('PRIVATE_PROFILE',
          detail: 'on=${makePrivate ? 'y' : 'n'} saved=y synced=${synced ? 'y' : 'n'} '
              'phone=${ProfilePrivacyRule.phoneVisibilityFor(private: makePrivate)}');
      messenger.showSnackBar(SnackBar(
        content: Text(!synced
            ? 'Saved; will update when online'
            : (makePrivate
                ? 'Your profile is private'
                : 'Your profile is public again')),
      ));
    } catch (e) {
      if (mounted) setState(() => _private = !makePrivate);
      ProfilePrivacyRule.ownPrivate.value = !makePrivate;
      messenger.showSnackBar(SnackBar(content: Text(cleanBlocError(e))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _loaded && !_saving;
    return Card(
      key: const ValueKey('profile_private_card'),
      child: ListTile(
        leading: const Icon(Icons.lock_outline),
        title: const Text('Private profile'),
        subtitle: Text(
          _private ? ProfilePrivacyRule.onText : ProfilePrivacyRule.offText,
          key: const ValueKey('profile_private_text'),
        ),
        onTap: enabled ? () => _change(!_private) : null,
        trailing: Switch(
          key: const ValueKey('profile_private_switch'),
          value: _private,
          onChanged: enabled ? _change : null,
        ),
      ),
    );
  }
}
