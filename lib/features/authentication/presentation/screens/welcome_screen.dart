import 'dart:async';
import 'dart:math' as math;
import 'package:locallink/core/theme/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:locallink/features/admin/data/actions/admin_action_doers.dart' show AdminActionDoers;
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/widgets/link_kit_290.dart';
import 'package:locallink/features/account/domain/account_repository_contract.dart';
import 'package:locallink/features/authentication/domain/authentication_repository_contract.dart';
import 'package:locallink/features/authentication/presentation/screens/setup_screen.dart';
import 'package:locallink/features/authentication/presentation/widgets/welcome_mesh_background.dart';
import 'package:locallink/features/recovery/domain/account_restoration_repository_contract.dart';
import 'package:locallink/features/recovery/domain/recovery_repository_contract.dart';
import 'package:locallink/features/transfer/domain/account_transfer_repository_contract.dart';

class WelcomeScreen extends StatelessWidget {
  final LocalLinkApi api;
  final AuthenticationRepositoryContract authentication;
  final LocalStore store;
  final AccountRepositoryContract accountRepository;
  final Future<void> Function() onSaved;
  final RecoveryRepositoryContract recoveryRepository;
  final AccountTransferRepositoryContract transferRepository;
  final AccountRestorationRepositoryContract restorationService;

  const WelcomeScreen({
    super.key,
    required this.api,
    required this.authentication,
    required this.store,
    required this.accountRepository,
    required this.onSaved,
    required this.recoveryRepository,
    required this.transferRepository,
    required this.restorationService,
  });

  void _openAuth(BuildContext context, {required bool register}) {
    // Bundle 220: the "signed out by admin" note goes once they act.
    unawaited(Future(() => store.writeSetting(AdminActionDoers.removedKey, ''))
        .catchError((Object _) {}));
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => SetupScreen(
          authentication: authentication,
          accountRepository: accountRepository,
          api: api,
          store: store,
          onSaved: onSaved,
          recoveryRepository: recoveryRepository,
          transferRepository: transferRepository,
          restorationService: restorationService,
          initialRegisterMode: register,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final view = WelcomeView(
      onCreateAccount: () => _openAuth(context, register: true),
      onLogIn: () => _openAuth(context, register: false),
    );
    // Bundle 220 (Q3): signed out / removed by an admin -> one short note.
    return FutureBuilder<String?>(
      future: Future(() => store.readSetting(AdminActionDoers.removedKey))
          .catchError((Object _) => null),
      builder: (context, snap) {
        final v = snap.data ?? '';
        if (v.isEmpty) return view;
        final text = v == 'signed_out'
            ? 'Signed out by admin. Your chats are still here. Log in again when the server is on.'
            : 'This phone was removed by admin. Your chats are still here. Log in again when the server is on.';
        return Stack(children: [
          view,
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: SafeArea(
              top: false,
              child: Material(
                key: const ValueKey('welcome_admin_note'),
                color: const Color(0xFFFFF4E5),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Row(children: [
                    const Icon(Icons.admin_panel_settings_outlined,
                        size: 18, color: Color(0xFFB54708)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(text,
                          style: const TextStyle(
                              fontSize: 13, color: Color(0xFF7A2E0E), letterSpacing: 0)),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ]);
      },
    );
  }
}

/// Bundle 152 (approved mock: Option A + Animation 1 "Mesh").
/// Bundle 288 (mock 288 welcome): live mesh at the top, gradient logo
/// badge, "LinkUp" gradient title, app-style feature cards, gradient
/// "Create account" + outlined "I already have an account".
class WelcomeView extends StatelessWidget {
  final VoidCallback onCreateAccount;
  final VoidCallback onLogIn;

  const WelcomeView({
    super.key,
    required this.onCreateAccount,
    required this.onLogIn,
  });

  static const String tagline = 'Chat and call, even without internet';

  /// Space above the logo (mock: 92 on a 800 dp phone; less on small ones).
  static double logoTop(double height) => (height * 0.115).clamp(28.0, 110.0);

  @override
  Widget build(BuildContext context) {
    final p = LinkKit.of(context);
    final dark = p.isDark;
    final topInset = MediaQuery.paddingOf(context).top;
    final top = logoTop(MediaQuery.sizeOf(context).height);
    // The mesh middle sits behind the logo middle (mock: box 330 high).
    final meshTop = topInset + top + 42 - 330 * 0.52;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: p.screen,
        body: Stack(
          children: [
            Positioned(
              top: meshTop,
              left: -6,
              right: -6,
              height: 330,
              child: const IgnorePointer(child: WelcomeMeshBackground()),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: constraints.maxHeight),
                    child: IntrinsicHeight(
                      child: Padding(
                        // Keep the content at most 420 wide on tablets while
                        // the column still fills the full screen height.
                        padding: EdgeInsets.symmetric(
                          horizontal: constraints.maxWidth > 420
                              ? (constraints.maxWidth - 420) / 2
                              : 0,
                        ),
                        child: _WelcomeContent(
                          logoTop: top,
                          onCreateAccount: onCreateAccount,
                          onLogIn: onLogIn,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WelcomeContent extends StatelessWidget {
  final double logoTop;
  final VoidCallback onCreateAccount;
  final VoidCallback onLogIn;

  const _WelcomeContent({
    required this.logoTop,
    required this.onCreateAccount,
    required this.onLogIn,
  });

  @override
  Widget build(BuildContext context) {
    final p = LinkKit.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(22, logoTop, 22, 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: _WelcomeLogo288()),
          const SizedBox(height: 16),
          Center(
            child: ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (rect) => const LinearGradient(
                colors: [Color(0xFF4D7DFF), Color(0xFF23D3E0)],
              ).createShader(rect),
              child: const Text(
                'LinkUp',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            WelcomeView.tagline,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: p.muted),
          ),
          const SizedBox(height: 20),
          const _FeatureCard(
            icon: Icons.chat_bubble_rounded,
            iconColor: Color(0xFF8EA6FF),
            iconBackground: Color(0x2E1E5BFF),
            title: 'Messages, photos, videos',
            subtitle: 'Nearby, Online or Offline',
          ),
          const _FeatureCard(
            icon: Icons.call_rounded,
            iconColor: Color(0xFF2DD4BF),
            iconBackground: Color(0x2E14A3A0),
            title: 'Voice calls',
            subtitle: 'Clear calls with people near you',
          ),
          const _FeatureCard(
            icon: Icons.lock_rounded,
            iconColor: Color(0xFFB8A6FF),
            iconBackground: Color(0x337C5CFF),
            title: 'Private and secure',
            subtitle: 'Your account, your chats',
          ),
          const Spacer(),
          const SizedBox(height: 20),
          BrandButton290(
            key: const ValueKey('welcome288-create'),
            onPressed: onCreateAccount,
            text: 'Create account',
          ),
          const SizedBox(height: 10),
          // Bundle 288: outlined second button (still a TextButton).
          TextButton(
            key: const ValueKey('welcome288-login'),
            onPressed: onLogIn,
            style: TextButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: p.isDark ? Colors.transparent : Colors.white,
              foregroundColor: p.isDark ? const Color(0xFFDBE3FF) : const Color(0xFF1E3A8A),
              shape: StadiumBorder(
                side: BorderSide(
                    color: p.isDark ? const Color(0xFF343A55) : const Color(0xFFC7CCE0), width: 1.5),
              ),
              textStyle: const TextStyle(fontFamily: LocalLinkLook.fontFamily, fontSize: 15, fontWeight: FontWeight.w700),
            ),
            child: const Text('I already have an account'),
          ),
        ],
      ),
    );
  }
}

/// Mock `.logo`: 84 gradient badge (radius 26) with a soft ring, breathing.
class _WelcomeLogo288 extends StatefulWidget {
  const _WelcomeLogo288();

  @override
  State<_WelcomeLogo288> createState() => _WelcomeLogo288State();
}

class _WelcomeLogo288State extends State<_WelcomeLogo288> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 3600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (LinkKit.calm(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'LinkUp logo',
      image: true,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, child) =>
            Transform.scale(scale: 1 + 0.04 * math.sin(_c.value * math.pi), child: child),
        child: Container(
          key: const ValueKey('welcome288-logo'),
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            gradient: LinkKit.brandGradient,
            borderRadius: BorderRadius.circular(26),
            boxShadow: const [
              BoxShadow(color: Color(0x1A23E0D8), spreadRadius: 7),
              BoxShadow(color: Color(0x731E5BFF), blurRadius: 30, offset: Offset(0, 12)),
            ],
          ),
          child: const Icon(Icons.forum_rounded, size: 42, color: Colors.white),
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String title;
  final String subtitle;

  const _FeatureCard({
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final p = LinkKit.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 9),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(18),
        boxShadow: p.cardShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconBackground,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, size: 21, color: iconColor),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: p.text)),
                const SizedBox(height: 1),
                Text(subtitle, style: TextStyle(fontSize: 12, color: p.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
