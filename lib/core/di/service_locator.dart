import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';

import '../../features/access/data/scope_api.dart';
import '../../features/access/data/scope_repository.dart';
import '../../features/access/presentation/home/scope_cubit.dart';
import '../../features/auth/data/auth_api.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/presentation/activation/activation_cubit.dart';
import '../../features/auth/presentation/controller/auth_controller.dart';
import '../../features/inventory/data/inventory_api.dart';
import '../../features/inventory/data/inventory_local_data_source.dart';
import '../../features/inventory/data/inventory_repository.dart';
import '../../features/inventory/data/inventory_sync_api.dart';
import '../../features/inventory/data/inventory_sync_service.dart';
import '../../features/inventory/data/outbox_local_data_source.dart';
import '../../features/inventory/data/outbox_repository.dart';
import '../../features/inventory/presentation/adjust/adjustment_cubit.dart';
import '../../features/inventory/presentation/count/stock_count_cubit.dart';
import '../../features/inventory/presentation/list/inventory_list_cubit.dart';
import '../../features/inventory/presentation/receive/receive_cubit.dart';
import '../../features/inventory/presentation/transfer/transfer_cubit.dart';
import '../../features/masterdata/data/hierarchy_api.dart';
import '../../features/masterdata/data/hierarchy_local_data_source.dart';
import '../../features/masterdata/data/hierarchy_repository.dart';
import '../../features/masterdata/data/hierarchy_sync_service.dart';
import '../../features/scanning/data/scan_api.dart';
import '../../features/scanning/data/scan_repository.dart';
import '../../features/scanning/presentation/scanner/scanner_cubit.dart';
import '../network/auth_interceptor.dart';
import '../network/connectivity_checker.dart';
import '../network/dio_factory.dart';
import '../network/session_provider.dart';
import '../storage/app_database.dart';
import '../sync/sync_coordinator.dart';
import '../storage/device_id_provider.dart';
import '../storage/remembered_activation_key_store.dart';
import '../storage/token_store.dart';

final GetIt sl = GetIt.instance;

/// Wires the object graph. Call once at startup before running the app.
///
/// Construction order matters: the authenticated Dio's [AuthInterceptor] needs
/// the [AuthController] (as [SessionProvider]) — so the controller is
/// registered first, then the interceptor is inserted at the front of the
/// authenticated client's chain.
Future<void> configureDependencies() async {
  // Storage
  sl.registerLazySingleton<TokenStore>(() => SecureTokenStore());
  sl.registerLazySingleton<DeviceIdProvider>(
      () => PersistentDeviceIdProvider());
  sl.registerLazySingleton<RememberedActivationKeyStore>(
      () => SecureRememberedActivationKeyStore());

  // Auth data (raw Dio — never intercepted/retried).
  final rawDio = DioFactory.createRawClient();
  sl.registerLazySingleton<AuthApi>(() => AuthApi(rawDio));
  sl.registerLazySingleton<AuthRepository>(
      () => AuthRepository(sl<AuthApi>(), sl<DeviceIdProvider>()));

  // App-wide session controller (also the SessionProvider).
  sl.registerLazySingleton<AuthController>(() => AuthController(
        repository: sl<AuthRepository>(),
        tokenStore: sl<TokenStore>(),
        rememberedKeyStore: sl<RememberedActivationKeyStore>(),
      ));
  sl.registerLazySingleton<SessionProvider>(() => sl<AuthController>());

  // Authenticated Dio + interceptor (Bearer; 401 invalidates the session).
  final authDio = DioFactory.createAuthenticatedClient();
  authDio.interceptors.insert(
    0,
    AuthInterceptor(sl<SessionProvider>()),
  );
  sl.registerLazySingleton<Dio>(() => authDio, instanceName: 'authenticated');

  // Access / scope data (`GET /me/scope`).
  sl.registerLazySingleton<ScopeApi>(
      () => ScopeApi(sl<Dio>(instanceName: 'authenticated')));
  sl.registerLazySingleton<ScopeRepository>(
      () => ScopeRepository(sl<ScopeApi>()));

  // Master-data offline store + sync.
  sl.registerLazySingleton<AppDatabase>(() => AppDatabase());
  sl.registerLazySingleton<HierarchyLocalDataSource>(
      () => HierarchyLocalDataSource(sl<AppDatabase>()));
  sl.registerLazySingleton<HierarchyApi>(
      () => HierarchyApi(sl<Dio>(instanceName: 'authenticated')));
  sl.registerLazySingleton<HierarchyRepository>(
      () => HierarchyRepository(sl<HierarchyLocalDataSource>()));
  sl.registerLazySingleton<HierarchySyncService>(() =>
      HierarchySyncService(sl<HierarchyLocalDataSource>(), sl<HierarchyApi>()));

  // Scanning (F3) — shares the authenticated Dio + persistent device id.
  sl.registerLazySingleton<ScanApi>(
      () => ScanApi(sl<Dio>(instanceName: 'authenticated')));
  sl.registerLazySingleton<ScanRepository>(
      () => ScanRepository(sl<ScanApi>(), sl<DeviceIdProvider>()));

  // Inventory (F4) — offline-first: local-only reads + background sync feeds +
  // the outbox mutation queue.
  sl.registerLazySingleton<InventoryApi>(
      () => InventoryApi(sl<Dio>(instanceName: 'authenticated')));
  sl.registerLazySingleton<InventorySyncApi>(
      () => InventorySyncApi(sl<Dio>(instanceName: 'authenticated')));
  sl.registerLazySingleton<InventoryLocalDataSource>(
      () => InventoryLocalDataSource(sl<AppDatabase>()));
  sl.registerLazySingleton<OutboxLocalDataSource>(
      () => OutboxLocalDataSource(sl<AppDatabase>()));
  sl.registerLazySingleton<InventoryRepository>(() => InventoryRepository(
        sl<InventoryLocalDataSource>(),
        sl<OutboxLocalDataSource>(),
      ));
  sl.registerLazySingleton<InventorySyncService>(() => InventorySyncService(
        sl<InventoryLocalDataSource>(),
        sl<InventorySyncApi>(),
        sl<HierarchyApi>(),
      ));
  sl.registerLazySingleton<OutboxRepository>(() => OutboxRepository(
        sl<OutboxLocalDataSource>(),
        sl<InventoryApi>(),
        sl<DeviceIdProvider>(),
      ));

  // Connectivity + the headless background sync coordinator (replaces the old
  // blocking /sync screen — sync never gates navigation to the Main Screen).
  sl.registerLazySingleton<ConnectivityChecker>(
      () => ConnectivityPlusChecker());
  sl.registerLazySingleton<SyncCoordinator>(() => SyncCoordinator(
        auth: sl<AuthController>(),
        connectivity: sl<ConnectivityChecker>(),
        hierarchySync: sl<HierarchySyncService>(),
        inventorySync: sl<InventorySyncService>(),
      ));

  // Presentation cubits (new instance per screen).
  sl.registerFactory<ActivationCubit>(() => ActivationCubit(
        sl<AuthRepository>(),
        sl<RememberedActivationKeyStore>(),
      ));
  sl.registerFactory<ScopeCubit>(() => ScopeCubit(sl<ScopeRepository>()));
  sl.registerFactory<ScannerCubit>(() => ScannerCubit(sl<ScanRepository>()));
  sl.registerFactory<InventoryListCubit>(
      () => InventoryListCubit(sl<InventoryRepository>()));
  sl.registerFactory<ReceiveCubit>(() => ReceiveCubit(sl<OutboxRepository>()));
  sl.registerFactory<TransferCubit>(
      () => TransferCubit(sl<OutboxRepository>()));
  sl.registerFactory<AdjustmentCubit>(
      () => AdjustmentCubit(sl<OutboxRepository>()));
  sl.registerFactory<StockCountCubit>(
      () => StockCountCubit(sl<OutboxRepository>()));
}
