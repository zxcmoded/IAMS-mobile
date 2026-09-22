import 'models/scope.dart';
import 'scope_api.dart';

/// Repository over the `/me/scope` endpoint. Thin today; the seam where scope
/// caching would later live.
class ScopeRepository {
  ScopeRepository(this._api);

  final ScopeApi _api;

  Future<Scope> loadScope() => _api.getScope();
}
