import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';

import '../../features/auth/data/auth_api.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/presentation/activation/activation_cubit.dart';
import '../../features/auth/presentation/controller/auth_controller.dart';
import '../../features/tenant/data/tenant_api.dart';
import '../../features/tenant/data/tenant_repository.dart';
import '../../features/tenant/presentation/access/access_cubit.dart';
import '../../features/tenant/presentation/scope/scope_cubit.dart';
import '../network/auth_interceptor.dart';
import '../network/dio_factory.dart';
import '../network/session_refresher.dart';
import '../storage/device_id_provider.dart';
import '../storage/token_store.dart';

final GetIt sl = GetIt.instance;

/// Wires the object graph. Call once at startup before running the app.
///
/// Construction order matters: the authenticated Dio's [AuthInterceptor] needs
/// the [AuthController] (as [SessionRefresher]) and uses the same Dio as its
/// retry client — so the controller is registered first, then the interceptor
/// is inserted at the front of the authenticated client's chain.
Future<void> configureDependencies() async {
  // Storage
  sl.registerLazySingleton<TokenStore>(() => SecureTokenStore());
  sl.registerLazySingleton<DeviceIdProvider>(
      () => PersistentDeviceIdProvider());

  // Auth data (raw Dio — never intercepted/retried).
  final rawDio = DioFactory.createRawClient();
  sl.registerLazySingleton<AuthApi>(() => AuthApi(rawDio));
  sl.registerLazySingleton<AuthRepository>(
      () => AuthRepository(sl<AuthApi>(), sl<DeviceIdProvider>()));

  // App-wide session controller (also the SessionRefresher).
  sl.registerLazySingleton<AuthController>(() => AuthController(
        repository: sl<AuthRepository>(),
        tokenStore: sl<TokenStore>(),
      ));
  sl.registerLazySingleton<SessionRefresher>(() => sl<AuthController>());

  // Authenticated Dio + interceptor (Bearer + refresh-on-401).
  final authDio = DioFactory.createAuthenticatedClient();
  authDio.interceptors.insert(
    0,
    AuthInterceptor(refresher: sl<SessionRefresher>(), retryClient: authDio),
  );
  sl.registerLazySingleton<Dio>(() => authDio, instanceName: 'authenticated');

  // Tenant data.
  sl.registerLazySingleton<TenantApi>(
      () => TenantApi(sl<Dio>(instanceName: 'authenticated')));
  sl.registerLazySingleton<TenantRepository>(
      () => TenantRepository(sl<TenantApi>()));

  // Presentation cubits (new instance per screen).
  sl.registerFactory<ActivationCubit>(
      () => ActivationCubit(sl<AuthRepository>()));
  sl.registerFactory<ScopeCubit>(() => ScopeCubit(sl<TenantRepository>()));
  sl.registerFactory<AccessCubit>(() => AccessCubit(sl<TenantRepository>()));
}
