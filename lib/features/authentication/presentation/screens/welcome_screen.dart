import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/widgets/gradient_pill_button.dart';
import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/features/account/domain/account_repository_contract.dart';
import 'package:locallink/features/authentication/domain/authentication_repository_contract.dart';
import 'package:locallink/features/authentication/presentation/screens/setup_screen.dart';
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
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Gradient hero with the animated chat-bubble motif.
            Expanded(
              flex: 5,
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LocalLinkBrand.heroGradient,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Bundle 137 (approved mock): the real app mark on the
                    // hero — white rounded card + splash logo, replacing the
                    // generic chat animation.
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(32),
                        boxShadow: const [
                          BoxShadow(
                              color: Color(0x33000000),
                              blurRadius: 24,
                              offset: Offset(0, 10)),
                        ],
                      ),
                      child: Image.asset(
                        'assets/brand/splash_logo.png',
                        width: 104,
                        height: 104,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                    Text(
                      'LocalLink',
                      style: textTheme.headlineLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: LocalLinkSpacing.xs),
                    Text(
                      'Messages that work anywhere',
                      style: textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withOpacity(0.85),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Rounded bottom sheet with the auth actions.
            Expanded(
              flex: 4,
              child: Container(
                width: double.infinity,
                transform: Matrix4.translationValues(0, -22, 0),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(32),
                  ),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    LocalLinkSpacing.screen,
                    36,
                    LocalLinkSpacing.screen,
                    24,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        GradientPillButton(
                          onPressed: () => _openAuth(context, register: false),
                          child: const Text('Log in'),
                        ),
                        const SizedBox(height: LocalLinkSpacing.md),
                        OutlinedButton(
                          onPressed: () => _openAuth(context, register: true),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 52),
                            side: const BorderSide(
                              color: LocalLinkBrand.gradientStart,
                              width: 1.5,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                LocalLinkRadius.pill,
                              ),
                            ),
                          ),
                          child: const Text('Create account'),
                        ),
                        const SizedBox(height: LocalLinkSpacing.lg),
                        Text(
                          'Works online, offline and on your local network.',
                          textAlign: TextAlign.center,
                          style: textTheme.bodySmall,
                        ),
                      ],
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
