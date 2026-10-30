import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/widgets/gradient_pill_button.dart';
import 'package:locallink/core/widgets/locallink_logo_mark.dart';
import 'package:locallink/core/theme/app_tokens.dart';
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
    return WelcomeView(
      onCreateAccount: () => _openAuth(context, register: true),
      onLogIn: () => _openAuth(context, register: false),
    );
  }
}

/// Bundle 152 (approved mock: Option A + Animation 1 "Mesh"): light welcome
/// screen with a soft blue glow, the faint mesh animation behind the logo,
/// three short cards that say what the app does, "Create account" as the
/// main button and "Log in" as a link under it.
class WelcomeView extends StatelessWidget {
  final VoidCallback onCreateAccount;
  final VoidCallback onLogIn;

  const WelcomeView({
    super.key,
    required this.onCreateAccount,
    required this.onLogIn,
  });

  static const String tagline = 'Chat and call, even without internet';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final background = dark ? theme.scaffoldBackgroundColor : Colors.white;
    final topInset = MediaQuery.paddingOf(context).top;
    // Tall phones: move the logo block down a little (and grow the mesh
    // with it) so the screen does not look top-heavy with a big empty gap.
    final extraTop =
        ((MediaQuery.sizeOf(context).height - 720) * 0.4).clamp(0.0, 90.0);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: background,
        body: Stack(
          children: [
            const Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _WelcomeGlowPainter()),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: topInset + 205 + extraTop,
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
                          extraTop: extraTop,
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
  final double extraTop;
  final VoidCallback onCreateAccount;
  final VoidCallback onLogIn;

  const _WelcomeContent({
    required this.extraTop,
    required this.onCreateAccount,
    required this.onLogIn,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        LocalLinkSpacing.screen,
        44 + extraTop,
        LocalLinkSpacing.screen,
        LocalLinkSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: LocalLinkLogoMark(width: 124)),
          const SizedBox(height: LocalLinkSpacing.lg),
          Center(
            child: ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (rect) => const LinearGradient(
                colors: [LocalLinkBrand.gradientStart, Color(0xFF16B8D6)],
              ).createShader(rect),
              child: Text(
                'LocalLink',
                style: textTheme.headlineLarge?.copyWith(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: LocalLinkSpacing.xs),
          Text(
            WelcomeView.tagline,
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(color: muted),
          ),
          const SizedBox(height: LocalLinkSpacing.xxl),
          const _FeatureCard(
            icon: Icons.chat_bubble_rounded,
            iconColor: LocalLinkBrand.gradientStart,
            iconBackground: Color(0xFFE3ECFF),
            title: 'Messages, photos, videos',
            subtitle: 'Nearby, Online or Offline',
          ),
          const SizedBox(height: LocalLinkSpacing.md),
          const _FeatureCard(
            icon: Icons.call_rounded,
            iconColor: Color(0xFF12A79D),
            iconBackground: Color(0xFFDFF8F6),
            title: 'Voice calls',
            subtitle: 'Clear calls with people near you',
          ),
          const SizedBox(height: LocalLinkSpacing.md),
          const _FeatureCard(
            icon: Icons.lock_rounded,
            iconColor: Color(0xFF7C5CFF),
            iconBackground: Color(0xFFEFE9FF),
            title: 'Private and secure',
            subtitle: 'Your account, your chats',
          ),
          const Spacer(),
          const SizedBox(height: LocalLinkSpacing.xxl),
          GradientPillButton(
            onPressed: onCreateAccount,
            child: const Text('Create account'),
          ),
          const SizedBox(height: LocalLinkSpacing.sm),
          TextButton(
            onPressed: onLogIn,
            style: TextButton.styleFrom(
              foregroundColor: LocalLinkBrand.gradientStart,
              minimumSize: const Size(0, 48),
            ),
            child: Text.rich(
              const TextSpan(
                children: [
                  TextSpan(text: 'I already have an account \u00b7 '),
                  TextSpan(
                    text: 'Log in',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: LocalLinkBrand.gradientStart,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
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
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: dark
            ? Colors.white.withValues(alpha: 0.07)
            : const Color(0xFFF4F7FC).withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(LocalLinkRadius.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: dark ? iconColor.withValues(alpha: 0.18) : iconBackground,
                borderRadius: BorderRadius.circular(LocalLinkRadius.sm),
              ),
              child: Icon(icon, size: 20, color: iconColor),
            ),
            const SizedBox(width: LocalLinkSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Soft cyan/blue glow at the top (wide ellipse fading to nothing).
class _WelcomeGlowPainter extends CustomPainter {
  const _WelcomeGlowPainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rx = size.width * 1.3;
    final ry = size.height * 0.55;
    canvas.save();
    canvas.translate(size.width / 2, 0);
    canvas.scale(1, ry / rx);
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          LocalLinkBrand.gradientEnd.withValues(alpha: 0.30),
          LocalLinkBrand.gradientStart.withValues(alpha: 0.14),
          LocalLinkBrand.gradientStart.withValues(alpha: 0),
        ],
        stops: const [0, 0.45, 0.75],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: rx));
    canvas.drawCircle(Offset.zero, rx, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WelcomeGlowPainter oldDelegate) => false;
}
