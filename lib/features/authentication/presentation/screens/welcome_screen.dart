import 'package:flutter/material.dart';

import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/features/account/domain/account_repository_contract.dart';
import 'package:locallink/features/authentication/domain/authentication_repository_contract.dart';
import 'package:locallink/features/authentication/presentation/screens/setup_screen.dart';
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

  const WelcomeScreen({
    super.key,
    required this.api,
    required this.authentication,
    required this.store,
    required this.accountRepository,
    required this.onSaved,
    required this.recoveryRepository,
    required this.transferRepository,
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
          initialRegisterMode: register,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(LocalLinkSpacing.screen),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.forum_rounded,
                      size: 42,
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: LocalLinkSpacing.xxl),
                  Text(
                    'LocalLink',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: LocalLinkSpacing.xxl),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => _openAuth(context, register: false),
                      child: const Text('Log in'),
                    ),
                  ),
                  const SizedBox(height: LocalLinkSpacing.sm),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => _openAuth(context, register: true),
                      child: const Text('Create account'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
