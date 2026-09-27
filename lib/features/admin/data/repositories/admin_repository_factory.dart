import 'package:locallink/core/network/api_http_client.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/features/admin/data/repositories/admin_repository.dart';
import 'package:locallink/features/admin/data/services/admin_service.dart';
import 'package:locallink/features/admin/domain/admin_repository_contract.dart';
import 'package:locallink/features/admin/domain/admin_repository_factory.dart';

final class DefaultAdminRepositoryFactory implements AdminRepositoryFactory {
  final LocalLinkApi _api;
  final ApiHttpClient _httpClient;
  const DefaultAdminRepositoryFactory({required LocalLinkApi api, required ApiHttpClient httpClient})
      : _api = api,
        _httpClient = httpClient;

  @override
  AdminRepositoryContract create(String token) =>
      AdminRepository(AdminService(_api, token, httpClient: _httpClient));
}
