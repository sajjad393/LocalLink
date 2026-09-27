import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/features/directory/domain/directory_models.dart';
import 'package:locallink/features/directory/domain/directory_repository_contract.dart';

class MyQrScreen extends StatelessWidget {
  final DirectoryProfile profile;
  final IdentityCryptoService crypto;
  final DirectoryRepositoryContract? repository;

  const MyQrScreen({
    super.key,
    required this.profile,
    required this.crypto,
    this.repository,
  });

  Future<String> _payload() async {
    final signingPublicKey = await crypto.signingPublicKey();
    final identityPublicKey = await crypto.publicKey();
    final unsigned = profile.copyWith(
      deviceId: profile.deviceId,
      phoneNumber: '',
      avatarUrl: '',
      signingPublicKey: signingPublicKey,
      identityPublicKey: identityPublicKey,
      signature: '',
      source: 'qr',
      syncedAt: '',
    );
    final signature = await crypto.signDirectoryProfile(unsigned.canonical());
    return jsonEncode({
      'v': 1,
      'profile': unsigned.toMap(),
      'signature': signature,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My QR Code'),
        actions: [
          IconButton(
            tooltip: 'Scan QR Code',
            onPressed: repository == null
                ? null
                : () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ContactQrScannerScreen(
                          crypto: crypto,
                          repository: repository!,
                        ),
                      ),
                    ),
            icon: const Icon(Icons.qr_code_scanner),
          ),
        ],
      ),
      body: FutureBuilder<String>(
        future: _payload(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Could not create your QR code. ${snapshot.error}'),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                children: [
                  QrImageView(data: snapshot.data!, size: 280),
                  const SizedBox(height: 20),
                  Text(
                    profile.displayName.isEmpty
                        ? '@${profile.username}'
                        : profile.displayName,
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Scan this code to verify my identity and add me as a contact.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class ContactQrScannerScreen extends StatefulWidget {
  final IdentityCryptoService crypto;
  final DirectoryRepositoryContract repository;
  final void Function(DirectoryProfile)? onFound;

  const ContactQrScannerScreen({
    super.key,
    required this.crypto,
    required this.repository,
    this.onFound,
  });

  @override
  State<ContactQrScannerScreen> createState() => _ContactQrScannerScreenState();
}

class _ContactQrScannerScreenState extends State<ContactQrScannerScreen> {
  final MobileScannerController scanner = MobileScannerController();
  bool done = false;
  bool resolving = false;
  String? error;

  @override
  void dispose() {
    scanner.dispose();
    super.dispose();
  }

  Future<void> _handle(String raw) async {
    if (done || resolving) return;
    setState(() {
      resolving = true;
      error = null;
    });

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['v']?.toString() != '1') {
        throw const FormatException('Unsupported LocalLink QR code');
      }
      final payload = Map<String, dynamic>.from(decoded);
      final profileMap = payload['profile'];
      final signature = payload['signature']?.toString() ?? '';
      if (profileMap is! Map || signature.isEmpty) {
        throw const FormatException('QR code is incomplete');
      }

      final profile = DirectoryProfile.fromMap(
        Map<String, dynamic>.from(profileMap),
      ).copyWith(
        signature: signature,
        source: 'qr',
        syncedAt: DateTime.now().toUtc().toIso8601String(),
      );
      if (!profile.isSigned ||
          !await widget.crypto.verifyDirectoryProfile(
            canonicalPayload: profile.canonical(),
            signature: profile.signature,
            signingPublicKey: profile.signingPublicKey,
          )) {
        throw const FormatException('QR signature verification failed');
      }

      final resolved = await widget.repository.importQrProfile(payload);
      if (resolved == null) {
        throw StateError('This contact is unavailable or blocked');
      }

      setState(() => done = true);
      widget.onFound?.call(resolved);
      if (widget.onFound == null && mounted) {
        Navigator.pop(context, resolved);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.toString().replaceFirst('Exception: ', '').replaceFirst('FormatException: ', '');
      });
    } finally {
      if (mounted) setState(() => resolving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan contact QR')),
      body: Stack(
        children: [
          MobileScanner(
            controller: scanner,
            onDetect: (capture) async {
              if (capture.barcodes.isEmpty) return;
              final raw = capture.barcodes.first.rawValue;
              if (raw != null && raw.isNotEmpty) await _handle(raw);
            },
          ),
          if (resolving)
            const Center(child: CircularProgressIndicator()),
          if (error != null)
            Positioned(
              left: 20,
              right: 20,
              bottom: 24,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(error!),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
