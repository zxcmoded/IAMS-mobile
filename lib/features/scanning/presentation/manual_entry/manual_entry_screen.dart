import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/router/app_routes.dart';
import '../../data/models/scan_result.dart';
import '../scanner/scanner_cubit.dart';

/// F3 Manual Entry — the code-field fallback for when the camera is
/// unavailable. Shares [ScannerCubit] with the Scanner so resolution + routing
/// behave identically; only the chrome differs (no viewport).
class ManualEntryScreen extends StatelessWidget {
  const ManualEntryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ScannerCubit>(
      create: (_) => sl<ScannerCubit>(),
      child: const _ManualEntryView(),
    );
  }
}

class _ManualEntryView extends StatefulWidget {
  const _ManualEntryView();

  @override
  State<_ManualEntryView> createState() => _ManualEntryViewState();
}

class _ManualEntryViewState extends State<_ManualEntryView> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final code = _controller.text.trim();
    if (code.isEmpty) return;
    context.read<ScannerCubit>().submitManual(code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Enter code')),
      body: SafeArea(
        child: BlocConsumer<ScannerCubit, ScannerState>(
          listenWhen: (prev, curr) =>
              curr.lastResult != null &&
              curr.lastResult != prev.lastResult &&
              !curr.resolving,
          listener: (context, state) {
            final r = state.lastResult!;
            if (r.resolvedType == ResolvedType.sku &&
                r.resolvedEntityId != null) {
              context.push('${AppRoutes.inventoryItem}?id=${r.resolvedEntityId}');
            }
          },
          builder: (context, state) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  key: const Key('manual_only_field'),
                  controller: _controller,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Code',
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.go,
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  key: const Key('manual_only_submit'),
                  onPressed: state.resolving ? null : _submit,
                  child: state.resolving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Resolve'),
                ),
                const SizedBox(height: 16),
                if (state.hasError)
                  Text(state.errorMessage ?? 'Scan failed.',
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error))
                else if (state.lastResult != null)
                  _ResultLine(result: state.lastResult!),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ResultLine extends StatelessWidget {
  const _ResultLine({required this.result});

  final ScanResult result;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (result.resolvedType) {
      ResolvedType.sku => ('SKU: ${result.label ?? ''}', Colors.green.shade800),
      ResolvedType.location => (
          'Location: ${result.label ?? ''}',
          Theme.of(context).colorScheme.primary
        ),
      ResolvedType.asset => ('Fixed asset (coming soon)',
          Theme.of(context).colorScheme.secondary),
      ResolvedType.blocked => (
          'Not in your scope',
          Theme.of(context).colorScheme.error
        ),
      ResolvedType.noMatch => (
          'No match for "${result.rawCode ?? ''}"',
          Theme.of(context).colorScheme.outline
        ),
      ResolvedType.unknown => (
          'Unrecognized result',
          Theme.of(context).colorScheme.outline
        ),
    };
    return Text(label, style: TextStyle(color: color, fontSize: 16));
  }
}
