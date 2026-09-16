import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/router/app_routes.dart';
import 'hierarchy_sync_cubit.dart';

/// Bootstrap screen shown once after authentication: it ensures the master-data
/// hierarchy is present in the local SQLite store (initial pull or incremental
/// catch-up) before the user reaches the browsing screens. On `complete` it
/// navigates on to `/companies` itself — the router redirect stays sync-unaware.
class HierarchySyncScreen extends StatelessWidget {
  const HierarchySyncScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<HierarchySyncCubit>(
      create: (_) => sl<HierarchySyncCubit>()..checkAndSync(),
      child: const _HierarchySyncView(),
    );
  }
}

class _HierarchySyncView extends StatelessWidget {
  const _HierarchySyncView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: BlocConsumer<HierarchySyncCubit, HierarchySyncState>(
          listenWhen: (prev, curr) => curr.isComplete && !prev.isComplete,
          listener: (context, state) {
            if (state.isComplete) context.go(AppRoutes.companies);
          },
          builder: (context, state) {
            if (state.isError) {
              return _ErrorState(
                message: state.errorMessage ?? 'Sync failed.',
                retryable: state.retryable,
                onRetry: () => context.read<HierarchySyncCubit>().retry(),
              );
            }
            return _ProgressState(state: state);
          },
        ),
      ),
    );
  }
}

class _ProgressState extends StatelessWidget {
  const _ProgressState({required this.state});

  final HierarchySyncState state;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 24),
              Text(
                'Preparing your data',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                _statusLine(state),
                key: const Key('sync_status_line'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _statusLine(HierarchySyncState state) {
    if (state.stage == SyncStage.checking || state.level == null) {
      return 'Checking your offline data…';
    }
    return 'Syncing ${_levelLabel(state.level!)}…';
  }

  String _levelLabel(String level) {
    switch (level) {
      case 'company':
        return 'companies';
      case 'location':
        return 'locations';
      case 'warehouse':
        return 'warehouses';
      case 'rack':
        return 'racks';
      case 'bin':
        return 'bins';
      default:
        return level;
    }
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.retryable,
    required this.onRetry,
  });

  final String message;
  final bool retryable;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.cloud_off, size: 64, color: scheme.error),
              const SizedBox(height: 24),
              Text(
                'Couldn\'t sync your data',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 32),
              if (retryable)
                FilledButton(
                  key: const Key('sync_retry'),
                  onPressed: onRetry,
                  child: const Text('Try again'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
