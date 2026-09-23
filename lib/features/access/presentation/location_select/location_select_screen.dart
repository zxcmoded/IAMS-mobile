import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/router/app_routes.dart';
import '../controller/selected_location_controller.dart';
import 'location_select_cubit.dart';

/// The one-time "Select Current Location" gate, shown right after activation for
/// a user who has not yet chosen a location (and re-openable later via the
/// dashboard's "Change" action). Lists the caller's assigned locations from
/// `GET /me/scope`, single-select, with a Continue button that persists the
/// choice via [SelectedLocationController] and returns to the dashboard.
class LocationSelectScreen extends StatelessWidget {
  const LocationSelectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Pre-select the current selection when re-opened to change it; on the
    // first-run gate there is none, so nothing is pre-selected.
    final current = sl<SelectedLocationController>().currentLocationId;
    return BlocProvider<LocationSelectCubit>(
      create: (_) => sl<LocationSelectCubit>()..load(preselectId: current),
      child: const _LocationSelectView(),
    );
  }
}

class _LocationSelectView extends StatelessWidget {
  const _LocationSelectView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('location_select_screen'),
      appBar: AppBar(title: const Text('Select location')),
      body: BlocBuilder<LocationSelectCubit, LocationSelectState>(
        builder: (context, state) {
          switch (state.status) {
            case LocationSelectStatus.initial:
            case LocationSelectStatus.loading:
              return const Center(child: CircularProgressIndicator());
            case LocationSelectStatus.error:
              return _ErrorState(
                message:
                    state.errorMessage ?? 'Could not load your locations.',
                onRetry: () => context.read<LocationSelectCubit>().refresh(),
              );
            case LocationSelectStatus.loaded:
              if (!state.hasLocations) return const _NoLocations();
              return _LoadedState(state: state);
          }
        },
      ),
    );
  }
}

class _LoadedState extends StatelessWidget {
  const _LoadedState({required this.state});

  final LocationSelectState state;

  Future<void> _continue(BuildContext context) async {
    final selectedId = state.selectedId;
    if (selectedId == null) return;
    // Capture the router before the async gap so we never touch a possibly
    // unmounted context after the await.
    final router = GoRouter.of(context);
    await sl<SelectedLocationController>().select(selectedId);
    // The redirect permits Home once a selection exists; navigate explicitly so
    // both the first-run gate and a later "Change" land back on the dashboard.
    router.go(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Choose the location you are working in. You can change it later '
              'from the dashboard.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ),
        Expanded(
          child: RadioGroup<String>(
            groupValue: state.selectedId,
            onChanged: (id) {
              if (id != null) {
                context.read<LocationSelectCubit>().choose(id);
              }
            },
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (final location in state.locations)
                  RadioListTile<String>(
                    key: Key('location_option_${location.id}'),
                    value: location.id,
                    title: Text(location.name),
                    secondary: Icon(
                      Icons.location_on_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
              ],
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('location_select_continue'),
                onPressed:
                    state.canContinue ? () => _continue(context) : null,
                child: const Text('Continue'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NoLocations extends StatelessWidget {
  const _NoLocations();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wrong_location_outlined, size: 48, color: scheme.outline),
            const SizedBox(height: 16),
            Text('No locations assigned',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'You have not been assigned to any locations yet. Contact your '
              'administrator.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off,
                size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 16),
            Text(
              message,
              key: const Key('location_select_error_message'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
