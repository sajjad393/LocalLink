import 'package:locallink/features/admin/domain/admin_repository_contract.dart';

abstract interface class AdminRepositoryFactory {
  AdminRepositoryContract create(String token);
}
