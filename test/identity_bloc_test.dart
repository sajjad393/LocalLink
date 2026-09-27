import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/account/data/models/identity_key_history.dart';
import 'package:locallink/features/account/domain/identity_repository_contract.dart';
import 'package:locallink/features/account/bloc/identity_bloc.dart';

class _FakeIdentityRepository implements IdentityRepositoryContract {
  @override
  Future<IdentitySnapshot> load() async => const IdentitySnapshot(
        keyVersion: 3,
        publicKey: 'CURRENT-KEY',
        history: [
          IdentityKeyHistoryEntry(keyVersion: 3, publicKey: 'CURRENT-KEY', active: true, createdAt: 'now', retiredAt: ''),
        ],
      );

  @override
  Future<IdentityRotationResult> rotate() async => const IdentityRotationResult(
        keyVersion: 4,
        publicKey: 'ROTATED-KEY',
        history: [
          IdentityKeyHistoryEntry(keyVersion: 4, publicKey: 'ROTATED-KEY', active: true, createdAt: 'later', retiredAt: ''),
        ],
      );
}

void main() {
  test('IdentityBloc loads a typed identity snapshot', () async {
    final controller = IdentityBloc(_FakeIdentityRepository());
    await controller.load();

    expect(controller.currentVersion, 3);
    expect(controller.currentPublicKey, 'CURRENT-KEY');
    expect(controller.history.single.keyVersion, 3);
    expect(controller.isLoading, isFalse);
  });

  test('IdentityBloc updates the current key after rotation', () async {
    final controller = IdentityBloc(_FakeIdentityRepository());
    await controller.rotate();

    expect(controller.currentVersion, 4);
    expect(controller.currentPublicKey, 'ROTATED-KEY');
    expect(controller.history.single.active, isTrue);
    expect(controller.isRotating, isFalse);
  });
}
