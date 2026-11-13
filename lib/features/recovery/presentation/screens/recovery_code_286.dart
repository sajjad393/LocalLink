import 'dart:async';
import 'dart:math' as math;

import 'package:locallink/core/theme/app_tokens.dart';
import 'package:flutter/material.dart';

import 'package:locallink/core/crypto/password_kdf.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/widgets/link_kit_290.dart';
import 'package:locallink/core/widgets/link_toast.dart';
import 'package:locallink/features/account/domain/account_repository_contract.dart';
import 'package:locallink/features/recovery/presentation/widgets/recovery_code_save_235.dart';

/// Bundle 286 (approved mock 286): the recovery code is easy to find and
/// to save.
///
/// * R-1 [RecoveryHomeCard286]: a card on top of Chats until the code is
///   saved ("Later" = 1 day). Right after Create account it shows the code
///   box without a password (the user just typed it).
/// * R-2 [RecoveryRow286]: Settings > Account > Backup and safety row with
///   a Not saved / Saved tag.
/// * R-3: the Profile row opens the same screens ([RecoveryCode286.open]).
///
/// The code itself is never written to the log.
enum RecoveryCardKind286 { fresh, notSaved, noCode }

/// Per-account flags (settings table, so they work with no server).
abstract final class RecoveryFlags286 {
  static String _user(LocalStore store, [String? username]) =>
      (username ?? store.username ?? '').trim().toLowerCase();

  static String savedKey(String user) => 'recovery_saved_286:$user';
  static String newKey(String user) => 'recovery_new_286:$user';
  static String laterKey(String user) => 'recovery_later_286:$user';

  /// Bumps when a flag changes (the Settings row and Home card listen).
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  static Future<String> _read(LocalStore store, String key) async {
    try {
      return (await store.readSetting(key)) ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<void> _write(LocalStore store, String key, String value) async {
    try {
      await store.writeSetting(key, value);
    } catch (_) {}
  }

  /// Create account (server or phone only): the fresh card with the code.
  static Future<void> markNew(LocalStore store, {String? username}) async {
    final user = _user(store, username);
    if (user.isEmpty) return;
    await _write(store, newKey(user), '1');
    await _write(store, savedKey(user), '');
    await _write(store, laterKey(user), '');
    AppLogger.info('RECOVERY_CARD', detail: 'new_account');
    changes.value++;
  }

  static Future<void> markSaved(LocalStore store, {required String from}) async {
    final user = _user(store);
    if (user.isEmpty) return;
    await _write(store, savedKey(user), '1');
    await _write(store, newKey(user), '');
    AppLogger.info('RECOVERY_CARD', detail: 'saved from=$from');
    changes.value++;
  }

  /// A new code was made: it is not saved anywhere yet.
  static Future<void> markNotSaved(LocalStore store) async {
    final user = _user(store);
    if (user.isEmpty) return;
    await _write(store, savedKey(user), '');
    changes.value++;
  }

  static Future<bool> isSaved(LocalStore store) async {
    final user = _user(store);
    if (user.isEmpty) return false;
    return await _read(store, savedKey(user)) == '1';
  }

  /// "Later": hidden for 1 day, then back as the normal (not fresh) card.
  static Future<void> later(LocalStore store, {DateTime? now}) async {
    final user = _user(store);
    if (user.isEmpty) return;
    final until = (now ?? DateTime.now()).add(const Duration(days: 1));
    await _write(store, laterKey(user), until.toUtc().toIso8601String());
    await _write(store, newKey(user), '');
    AppLogger.info('RECOVERY_CARD', detail: 'later');
    changes.value++;
  }
}

abstract final class RecoveryCode286 {
  /// Which Home card to show now (null = none).
  static Future<RecoveryCardKind286?> cardKind(LocalStore store, {DateTime? now}) async {
    final user = (store.username ?? '').trim().toLowerCase();
    if (user.isEmpty) return null;
    if (await RecoveryFlags286.isSaved(store)) return null;
    final later = DateTime.tryParse(await RecoveryFlags286._read(store, RecoveryFlags286.laterKey(user)));
    if (later != null && (now ?? DateTime.now()).toUtc().isBefore(later.toUtc())) return null;
    if ((store.localRecoveryCode ?? '').trim().isEmpty) return RecoveryCardKind286.noCode;
    if (await RecoveryFlags286._read(store, RecoveryFlags286.newKey(user)) == '1') {
      return RecoveryCardKind286.fresh;
    }
    return RecoveryCardKind286.notSaved;
  }

  /// The password checked with the copy saved on this phone (the same check
  /// as offline sign-in), so it works with no server.
  /// 'ok' / 'wrong' / 'no_copy' (no copy of this account on the phone).
  static Future<String> checkPassword(LocalStore store, String password) async {
    final user = (store.username ?? '').trim().toLowerCase();
    var known = false;
    for (final copy in [store.offlinePending, store.offlineLoginAccount]) {
      if (copy == null || user.isEmpty) continue;
      if (copy['username']?.toString().trim().toLowerCase() != user) continue;
      known = true;
      if (password.isEmpty) continue;
      if (await PasswordKdf.verifyAsync(
        password,
        copy['pwd_salt']?.toString() ?? '',
        copy['pwd_hash']?.toString() ?? '',
      )) {
        return 'ok';
      }
    }
    return known ? 'wrong' : 'no_copy';
  }

  /// A new code: from the server when it answers (the phone keeps the same
  /// code), else made on this phone (it goes up with the account later).
  static Future<String> makeNew(AccountRepositoryContract accounts, LocalStore store) async {
    String code;
    var where = 'server';
    try {
      code = await accounts.rotateRecoveryCode();
      try {
        await store.updateLocalRecoveryCode(code);
      } catch (_) {}
    } catch (_) {
      where = 'phone';
      code = await store.rotateLocalRecoveryCode();
    }
    await RecoveryFlags286.markNotSaved(store);
    AppLogger.info('RECOVERY_VIEW', detail: 'new_code from=$where');
    return code;
  }

  /// Password first, then the code screen. [makeNew] = "Make my code".
  static Future<void> open(
    BuildContext context, {
    required LocalStore store,
    required AccountRepositoryContract accounts,
    bool makeNew = false,
  }) async {
    AppLogger.info('RECOVERY_VIEW', detail: 'open${makeNew ? ' make' : ''}');
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => RecoveryPasswordScreen286(store: store, accounts: accounts, makeNew: makeNew),
    ));
  }
}

// ------------------------------------------------------------------ R-1

/// Mock `.rc`: the Home card (above My links). No x button: "Later" does it.
class RecoveryHomeCard286 extends StatefulWidget {
  final LocalStore store;
  final AccountRepositoryContract accounts;

  /// Another Home card / note is on screen: one card at a time.
  final bool hidden;
  final DateTime Function()? clock;

  const RecoveryHomeCard286({
    super.key,
    required this.store,
    required this.accounts,
    this.hidden = false,
    this.clock,
  });

  @override
  State<RecoveryHomeCard286> createState() => _RecoveryHomeCard286State();
}

class _RecoveryHomeCard286State extends State<RecoveryHomeCard286> with TickerProviderStateMixin {
  RecoveryCardKind286? _kind;
  String _code = '';
  bool _leaving = false;
  bool _loggedShown = false;
  bool _ringDone = false;
  late final AnimationController _in =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
  late final AnimationController _ring =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 3000));

  @override
  void initState() {
    super.initState();
    RecoveryFlags286.changes.addListener(_load);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant RecoveryHomeCard286 oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hidden != widget.hidden) unawaited(_load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncRing();
  }

  /// The ring breathes a few times when the card shows, then rests (no
  /// endless animation on the Chats list).
  void _syncRing() {
    if (_kind != null && !LinkKit.calm(context)) {
      if (!_ring.isAnimating && !_ringDone) {
        _ringDone = true;
        unawaited(_ring.repeat(count: 4).orCancel.then((_) {}, onError: (Object _) {}));
      }
    } else {
      _ring.stop();
      _ringDone = false;
    }
  }

  @override
  void dispose() {
    RecoveryFlags286.changes.removeListener(_load);
    _in.dispose();
    _ring.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (widget.hidden) {
      if (mounted && _kind != null) setState(() => _kind = null);
      return;
    }
    final kind = await RecoveryCode286.cardKind(widget.store, now: widget.clock?.call());
    if (!mounted || _leaving) return;
    if (kind == null) {
      if (_kind != null) unawaited(_leave());
      return;
    }
    final was = _kind;
    setState(() {
      _kind = kind;
      _code = widget.store.localRecoveryCode ?? '';
    });
    _syncRing();
    if (was == null) {
      if (LinkKit.calm(context)) {
        _in.value = 1;
      } else {
        unawaited(_in.forward(from: 0));
      }
    }
    if (!_loggedShown) {
      _loggedShown = true;
      AppLogger.info('RECOVERY_CARD', detail: 'shown kind=${kind.name}');
    }
  }

  /// The card slides away, then is gone.
  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    try {
      if (LinkKit.calm(context)) {
        _in.value = 0;
      } else {
        await _in.animateBack(0, duration: const Duration(milliseconds: 350), curve: Curves.easeInCubic);
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _kind = null;
      _leaving = false;
    });
    _syncRing();
  }

  Future<void> _saved(String from) async {
    if (_leaving) return;
    LinkToast.show(context, 'Recovery code saved', kind: LinkToastKind.done);
    final leaving = _leave();
    await RecoveryFlags286.markSaved(widget.store, from: from);
    await leaving;
  }

  Future<void> _later() async {
    if (_leaving) return;
    final leaving = _leave();
    await RecoveryFlags286.later(widget.store, now: widget.clock?.call());
    await leaving;
  }

  Future<void> _openScreen({bool make = false}) async {
    await RecoveryCode286.open(context, store: widget.store, accounts: widget.accounts, makeNew: make);
    if (mounted) unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final kind = _kind;
    if (kind == null || widget.hidden) return const SizedBox.shrink();
    final p = LinkKit.of(context);
    final user = (widget.store.username ?? '').trim();
    final (title, words) = switch (kind) {
      RecoveryCardKind286.fresh => (
          'Save your recovery code',
          'If you lose this phone, it is the only way back into @$user.',
        ),
      RecoveryCardKind286.notSaved => (
          'Save your recovery code',
          'You have not saved it yet. Keep it safe in case this phone is lost.',
        ),
      RecoveryCardKind286.noCode => (
          'Make a recovery code',
          'This account has no recovery code on this phone yet.',
        ),
    };
    final curve = CurvedAnimation(parent: _in, curve: const Cubic(0.2, 0.8, 0.2, 1));
    final card = Container(
      key: const ValueKey('rc286-card'),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: p.isDark ? const Color(0x4D8EA6FF) : const Color(0xFFC7D2FE)),
        gradient: LinearGradient(
          begin: const Alignment(-0.77, -0.64),
          end: const Alignment(0.77, 0.64),
          colors: p.isDark
              ? const [Color(0x331E5BFF), Color(0x1A23B5D8), Color(0x1A23B5D8)]
              : const [Color(0xFFE7EDFF), Color(0xFFE6F7FB), Color(0xFFE6F7FB)],
          stops: p.isDark ? const [0, 0.7, 1] : const [0, 0.75, 1],
        ),
      ),
      child: Stack(clipBehavior: Clip.none, children: [
        // Mock `.rc:before`: soft cyan glow top right.
        Positioned(
          right: -54,
          top: -54,
          child: IgnorePointer(
            child: Container(
              width: 130,
              height: 130,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [Color(0x2E23E0D8), Color(0x0023E0D8)], stops: [0, 0.7]),
              ),
            ),
          ),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            _ShieldTile286(ring: _ring),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: p.isDark ? Colors.white : const Color(0xFF111827))),
                const SizedBox(height: 2),
                Text(words,
                    style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: p.isDark ? const Color(0xFFB9BDD0) : const Color(0xFF4B5563))),
              ]),
            ),
          ]),
          if (kind == RecoveryCardKind286.fresh) ...[
            const SizedBox(height: 12),
            RecoveryCodeBox235(key: const ValueKey('rc286-box'), code: _code, onCard: true, compact: true),
            const SizedBox(height: 10),
            SaveOnWhatsApp235(
              buttonKey: const ValueKey('rc286-whatsapp'),
              code: _code,
              username: user,
              height: 44,
              hint: false,
              onSaved: () => _saved('whatsapp'),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(children: [
                InkWell(
                  key: const ValueKey('rc286-saved'),
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => unawaited(_saved('button')),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.check_rounded,
                          size: 15, color: p.isDark ? const Color(0xFF86EFAC) : const Color(0xFF067647)),
                      const SizedBox(width: 4),
                      Text('I saved it',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: p.isDark ? const Color(0xFF86EFAC) : const Color(0xFF067647))),
                    ]),
                  ),
                ),
                const Spacer(),
                InkWell(
                  key: const ValueKey('rc286-later'),
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => unawaited(_later()),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                    child: Text('Later',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: p.isDark ? const Color(0xFF9497A5) : const Color(0xFF6B7080))),
                  ),
                ),
              ]),
            ),
          ] else ...[
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: _CardButton286(
                  key: const ValueKey('rc286-open'),
                  text: kind == RecoveryCardKind286.noCode ? 'Make my code' : 'Show my code',
                  icon: kind == RecoveryCardKind286.noCode ? Icons.refresh_rounded : Icons.visibility,
                  onTap: () => unawaited(_openScreen(make: kind == RecoveryCardKind286.noCode)),
                ),
              ),
              const SizedBox(width: 8),
              _CardButton286(
                key: const ValueKey('rc286-later'),
                text: 'Later',
                outlined: true,
                onTap: () => unawaited(_later()),
              ),
            ]),
          ],
        ]),
      ]),
    );
    return SizeTransition(
      sizeFactor: curve,
      alignment: Alignment.topCenter,
      child: AnimatedBuilder(
        animation: curve,
        builder: (_, child) => Opacity(
          opacity: curve.value.clamp(0.0, 1.0),
          child: Transform.translate(offset: Offset(0, 14 * (1 - curve.value)), child: child),
        ),
        child: Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 4), child: card),
      ),
    );
  }
}

/// Mock `.rc .sh`: 42 px gradient shield tile with a breathing ring.
class _ShieldTile286 extends StatelessWidget {
  final Animation<double> ring;
  const _ShieldTile286({required this.ring});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      height: 42,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned(
          left: -5,
          top: -5,
          right: -5,
          bottom: -5,
          child: AnimatedBuilder(
            animation: ring,
            builder: (_, __) {
              final b = 0.5 - 0.5 * math.cos(2 * math.pi * ring.value);
              return Opacity(
                opacity: 1 - 0.4 * b,
                child: Transform.scale(
                  scale: 1 + 0.07 * b,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0x5923E0D8), width: 2),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinkKit.brandGradient,
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [BoxShadow(color: Color(0x591E5BFF), blurRadius: 16, offset: Offset(0, 6))],
            ),
            child: const Icon(Icons.security, size: 22, color: Colors.white),
          ),
        ),
      ]),
    );
  }
}

/// Mock `.rc .b1` (44 px): brand gradient, or outlined "Later".
class _CardButton286 extends StatelessWidget {
  final String text;
  final IconData? icon;
  final bool outlined;
  final VoidCallback onTap;
  const _CardButton286({super.key, required this.text, this.icon, this.outlined = false, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = LinkKit.of(context);
    final fg = outlined ? (p.isDark ? const Color(0xFFDBE3FF) : const Color(0xFF1E3A8A)) : Colors.white;
    return Container(
      height: 44,
      decoration: BoxDecoration(
        gradient: outlined ? null : LinkKit.brandGradient,
        color: outlined ? (p.isDark ? Colors.transparent : Colors.white) : null,
        borderRadius: BorderRadius.circular(22),
        border: outlined
            ? Border.all(color: p.isDark ? const Color(0x738EA6FF) : const Color(0xFFA5B4FC), width: 1.5)
            : null,
        boxShadow: outlined
            ? null
            : const [BoxShadow(color: Color(0x4D1E5BFF), blurRadius: 16, offset: Offset(0, 6))],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
              if (icon != null) ...[
                Icon(icon, size: 17, color: fg),
                const SizedBox(width: 7),
              ],
              // Small phone + big text (320 dp, 1.3x): shrink the words a little, never overflow.
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(text,
                      maxLines: 1, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: fg)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ R-2

/// Settings > Account > Backup and safety: "Recovery code" + Not saved /
/// Saved tag (replaces the old grey note).
class RecoveryRow286 extends StatefulWidget {
  final LocalStore store;
  final AccountRepositoryContract accounts;
  const RecoveryRow286({super.key, required this.store, required this.accounts});

  @override
  State<RecoveryRow286> createState() => _RecoveryRow286State();
}

class _RecoveryRow286State extends State<RecoveryRow286> {
  bool? _saved;

  @override
  void initState() {
    super.initState();
    RecoveryFlags286.changes.addListener(_load);
    unawaited(_load());
  }

  @override
  void dispose() {
    RecoveryFlags286.changes.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final saved = await RecoveryFlags286.isSaved(widget.store);
    if (mounted && saved != _saved) setState(() => _saved = saved);
  }

  @override
  Widget build(BuildContext context) {
    final p = LinkKit.of(context);
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final saved = _saved == true;
    final (tag, fg, bg, key) = saved
        ? ('Saved', p.isDark ? const Color(0xFF86EFAC) : const Color(0xFF067647),
            p.isDark ? const Color(0x2122C55E) : const Color(0xFFDCFCE7), 'rc286-tag-saved')
        : ('Not saved', p.isDark ? const Color(0xFFFBBF24) : const Color(0xFF9A5B06),
            p.isDark ? const Color(0x24F59E0B) : const Color(0xFFFEF3C7), 'rc286-tag-not-saved');
    return DecoratedBox(
      // Mock `.sr.new`: a soft blue wash while it is not saved.
      decoration: BoxDecoration(
        gradient: saved || _saved == null
            ? null
            : LinearGradient(colors: [
                p.isDark ? const Color(0x1F1E5BFF) : const Color(0xFFEEF2FF),
                (p.isDark ? const Color(0x1F1E5BFF) : const Color(0xFFEEF2FF)).withValues(alpha: 0),
              ]),
      ),
      child: ListTile(
        key: const ValueKey('rc286-row'),
        leading: Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(gradient: LinkKit.brandGradient, shape: BoxShape.circle),
          child: const Icon(Icons.security, size: 20, color: Colors.white),
        ),
        title: Row(children: [
          Flexible(child: Text('Recovery code', style: text.titleSmall, overflow: TextOverflow.ellipsis)),
          if (_saved != null) ...[
            const SizedBox(width: 6),
            Container(
              key: ValueKey(key),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
              child: Text(tag, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: fg)),
            ),
          ],
        ]),
        subtitle: Text('Your way back in if this phone is lost',
            style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant, letterSpacing: 0)),
        trailing: Icon(Icons.chevron_right, color: colors.onSurfaceVariant, size: 20),
        onTap: () => RecoveryCode286.open(context, store: widget.store, accounts: widget.accounts),
      ),
    );
  }
}

// ------------------------------------------------------------ screens

AppBar _bar286(BuildContext context) {
  final p = LinkKit.of(context);
  return AppBar(
    title: const Text('Recovery code'),
    backgroundColor: p.screen,
    surfaceTintColor: Colors.transparent,
    foregroundColor: p.text,
  );
}

/// Password first (checked on this phone, works with no server).
class RecoveryPasswordScreen286 extends StatefulWidget {
  final LocalStore store;
  final AccountRepositoryContract accounts;
  final bool makeNew;
  const RecoveryPasswordScreen286({super.key, required this.store, required this.accounts, this.makeNew = false});

  static const String wrongText = 'Wrong password. Your code stays hidden.';
  static const String noCopyText = 'This phone has no copy of your password. Log in again on this phone, then try.';

  @override
  State<RecoveryPasswordScreen286> createState() => _RecoveryPasswordScreen286State();
}

class _RecoveryPasswordScreen286State extends State<RecoveryPasswordScreen286> {
  final _password = TextEditingController();
  bool _hide = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _password.addListener(_typed);
  }

  void _typed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _password.removeListener(_typed);
    _password.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await RecoveryCode286.checkPassword(widget.store, _password.text);
    if (!mounted) return;
    AppLogger.info('RECOVERY_VIEW', detail: 'password $result');
    if (result != 'ok') {
      setState(() {
        _busy = false;
        _error = result == 'no_copy' ? RecoveryPasswordScreen286.noCopyText : RecoveryPasswordScreen286.wrongText;
      });
      return;
    }
    var code = widget.store.localRecoveryCode ?? '';
    if (widget.makeNew || code.trim().isEmpty) {
      try {
        code = await RecoveryCode286.makeNew(widget.accounts, widget.store);
      } catch (_) {
        AppLogger.warning('RECOVERY_VIEW', detail: 'new_code_failed');
        if (!mounted) return;
        setState(() => _busy = false);
        LinkToast.show(context, 'Could not make a new code. Try again.', kind: LinkToastKind.error);
        return;
      }
    }
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      builder: (_) => RecoveryCodeScreen286(store: widget.store, accounts: widget.accounts, code: code),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final p = LinkKit.of(context);
    return Scaffold(
      backgroundColor: p.screen,
      appBar: _bar286(context),
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 32),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const HeroRow290(
              icon: Icons.lock,
              title: 'Enter your password',
              subtitle: 'Only you should see your recovery code.',
            ),
            LinkField290(
              fieldKey: const ValueKey('rc286-password'),
              controller: _password,
              label: 'Password',
              icon: Icons.lock_outline_rounded,
              obscureText: _hide,
              enabled: !_busy,
              error: _error != null,
              autofocus: true,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              trailing: LinkEye290(hidden: _hide, onTap: () => setState(() => _hide = !_hide)),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => unawaited(_check()),
            ),
            if (_error != null)
              LinkUnderLine290(_error!, key: const ValueKey('rc286-wrong'), error: true)
            else
              // 295-E: 10 px between the password box and "Show my code" (they touched).
              const SizedBox(key: ValueKey('rc295-gap'), height: 10),
            BrandButton290(
              key: const ValueKey('rc286-show'),
              onPressed: _password.text.isEmpty ? null : () => unawaited(_check()),
              text: 'Show my code',
              loading: _busy,
            ),
            if (_error == null) const LinkNote290('Works without the server too.'),
          ]),
        ),
      ),
    );
  }
}

/// The code: big, Hide / Copy, Save on WhatsApp, 2 tips, Make a new code.
class RecoveryCodeScreen286 extends StatefulWidget {
  final LocalStore store;
  final AccountRepositoryContract accounts;
  final String code;
  const RecoveryCodeScreen286({super.key, required this.store, required this.accounts, required this.code});

  @override
  State<RecoveryCodeScreen286> createState() => _RecoveryCodeScreen286State();
}

class _RecoveryCodeScreen286State extends State<RecoveryCodeScreen286> {
  late String _code = widget.code;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    AppLogger.info('RECOVERY_VIEW', detail: 'shown');
  }

  Future<void> _saved() async {
    await RecoveryFlags286.markSaved(widget.store, from: 'whatsapp_screen');
    if (mounted) LinkToast.show(context, 'Recovery code saved', kind: LinkToastKind.done);
  }

  Future<void> _makeNew() async {
    final p = LinkKit.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Make a new code?', style: TextStyle(color: p.text, fontSize: 18, fontWeight: FontWeight.w700)),
        content: Text('Your old code stops working.', style: TextStyle(color: p.muted, fontSize: 14, height: 1.4)),
        actions: [
          TextButton(
            key: const ValueKey('rc286-new-no'),
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: p.muted),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const ValueKey('rc286-new-yes'),
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: p.link,
              textStyle: const TextStyle(fontFamily: LocalLinkLook.fontFamily, fontWeight: FontWeight.w700),
            ),
            child: const Text('Make new code'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final code = await RecoveryCode286.makeNew(widget.accounts, widget.store);
      if (!mounted) return;
      setState(() => _code = code);
    } catch (_) {
      AppLogger.warning('RECOVERY_VIEW', detail: 'new_code_failed');
      if (mounted) LinkToast.show(context, 'Could not make a new code. Try again.', kind: LinkToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _tip(LinkPalette p, String text) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 7),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.check_rounded, size: 16, color: p.isDark ? const Color(0xFF86EFAC) : const Color(0xFF067647)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: p.isDark ? const Color(0xFFB5B8C5) : const Color(0xFF4B5563))),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final p = LinkKit.of(context);
    final user = (widget.store.username ?? '').trim();
    return Scaffold(
      backgroundColor: p.screen,
      appBar: _bar286(context),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 32),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const HeroRow290(
              icon: Icons.security,
              title: 'Your recovery code',
              below: Align(
                alignment: Alignment.centerLeft,
                child: LivePill290(text: 'Saved on this phone'),
              ),
            ),
            RecoveryCodeBox235(
              key: const ValueKey('rc286-code'),
              code: _code,
              label: '@$user',
              big: true,
              startShown: true,
            ),
            const SizedBox(height: 14),
            SaveOnWhatsApp235(
              buttonKey: const ValueKey('rc286-screen-whatsapp'),
              code: _code,
              username: user,
              onSaved: _saved,
            ),
            const SizedBox(height: 10),
            _tip(p, 'Use it on Forgot password if this phone is lost. Works offline.'),
            _tip(p, 'Never share it. LinkUp and the admin never ask for it.'),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                key: const ValueKey('rc286-new'),
                onPressed: _busy ? null : () => unawaited(_makeNew()),
                style: TextButton.styleFrom(
                  foregroundColor: p.isDark ? const Color(0xFFA9B8FF) : const Color(0xFF1E5BFF),
                  textStyle: const TextStyle(fontFamily: LocalLinkLook.fontFamily, fontSize: 14, fontWeight: FontWeight.w600),
                ),
                icon: _busy
                    ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh_rounded, size: 15),
                label: const Text('Make a new code'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
