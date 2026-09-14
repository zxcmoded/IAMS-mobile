import 'models/access.dart';
import 'models/scope.dart';
import 'tenant_api.dart';

/// Repository over the tenant scope + access endpoints. Thin today; the seam
/// where scope caching / policyVersion drift detection (BR-TC-007) and the
/// offline batch re-validation (F11/BR-TC-008) will live later.
class TenantRepository {
  TenantRepository(this._api);

  final TenantApi _api;

  Future<Scope> loadScope() => _api.getScope();

  Future<AccessDecision> evaluateAccess(AccessRequest request) =>
      _api.evaluate(request);
}
