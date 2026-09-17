import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/router/app_routes.dart';
import '../../data/models/scan_result.dart';
import 'scanner_cubit.dart';

/// F3 Scanner. Because no camera/barcode package is wired in this phase (see the
/// report), the viewport is a placeholder with reticle + flash/batch toggles,
/// and code capture happens through the always-available manual-entry field —
/// the same code path a real detector callback would drive (`cubit.onScanned`).
/// All five states are represented: scanning · permission-denied · no-match ·
/// resolved · cross-tenant blocked.
class ScannerScreen extends StatelessWidget {
  const ScannerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ScannerCubit>(
      create: (_) => sl<ScannerCubit>(),
      child: const _ScannerView(),
    );
  }
}

class _ScannerView extends StatelessWidget {
  const _ScannerView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan'),
        actions: [
          BlocBuilder<ScannerCubit, ScannerState>(
            buildWhen: (a, b) => a.batchMode != b.batchMode,
            builder: (context, state) => Row(
              children: [
                const Text('Batch'),
                Switch(
                  key: const Key('batch_toggle'),
                  value: state.batchMode,
                  onChanged: (_) => context.read<ScannerCubit>().toggleBatch(),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: BlocConsumer<ScannerCubit, ScannerState>(
          // Route only on a *new* successfully-resolved SKU while not batching.
          listenWhen: (prev, curr) =>
              curr.lastResult != null &&
              curr.lastResult != prev.lastResult &&
              !curr.resolving,
          listener: _onResult,
          builder: (context, state) {
            return Column(
              children: [
                Expanded(child: _Viewport(state: state)),
                _ResultPanel(state: state),
                _ManualEntry(state: state),
              ],
            );
          },
        ),
      ),
    );
  }

  void _onResult(BuildContext context, ScannerState state) {
    final result = state.lastResult!;
    // In batch mode we never navigate away — results accumulate in the history.
    if (state.batchMode) return;

    switch (result.resolvedType) {
      case ResolvedType.sku:
        if (result.resolvedEntityId != null) {
          context.push('${AppRoutes.inventoryItem}?id=${result.resolvedEntityId}');
        }
      case ResolvedType.asset:
        // Reserved for F5 — tolerate without crashing (never emitted today).
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Fixed assets are coming soon.'),
        ));
      case ResolvedType.location:
      case ResolvedType.noMatch:
      case ResolvedType.blocked:
      case ResolvedType.unknown:
        // Rendered inline by _ResultPanel — no navigation target this phase.
        break;
    }
  }
}

class _Viewport extends StatelessWidget {
  const _Viewport({required this.state});

  final ScannerState state;

  @override
  Widget build(BuildContext context) {
    if (state.cameraPermissionDenied) {
      return const _PermissionDenied();
    }
    return Container(
      color: Colors.black87,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Reticle.
          Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white70, width: 2),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          if (state.resolving)
            const CircularProgressIndicator(color: Colors.white),
          Positioned(
            bottom: 16,
            child: Text(
              state.resolving ? 'Resolving…' : 'Point at a barcode or QR code',
              style: const TextStyle(color: Colors.white70),
            ),
          ),
          Positioned(
            top: 16,
            right: 16,
            child: IconButton(
              key: const Key('flash_toggle'),
              tooltip: 'Flash',
              icon: Icon(
                state.flashOn ? Icons.flash_on : Icons.flash_off,
                color: Colors.white,
              ),
              onPressed: () => context.read<ScannerCubit>().toggleFlash(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders the resolved / no-match / blocked / error banner from the last scan.
class _ResultPanel extends StatelessWidget {
  const _ResultPanel({required this.state});

  final ScannerState state;

  @override
  Widget build(BuildContext context) {
    if (state.hasError) {
      return _Banner(
        key: const Key('scan_error'),
        icon: Icons.error_outline,
        color: Theme.of(context).colorScheme.error,
        title: 'Scan failed',
        detail: state.errorMessage ?? 'Please try again.',
      );
    }
    final result = state.lastResult;
    if (result == null) return const SizedBox.shrink();

    switch (result.resolvedType) {
      case ResolvedType.sku:
        return _Banner(
          key: const Key('scan_resolved'),
          icon: Icons.inventory_2,
          color: Colors.green.shade800,
          title: 'SKU: ${result.label ?? result.rawCode ?? 'item'}',
          detail: state.batchMode
              ? 'Added to batch. Keep scanning.'
              : 'Opening item…',
        );
      case ResolvedType.location:
        return _Banner(
          key: const Key('scan_location'),
          icon: Icons.place,
          color: Theme.of(context).colorScheme.primary,
          title: 'Location: ${result.label ?? result.rawCode ?? 'bin'}',
          detail: 'Bin recognized.',
        );
      case ResolvedType.asset:
        return _Banner(
          key: const Key('scan_asset'),
          icon: Icons.qr_code_2,
          color: Theme.of(context).colorScheme.secondary,
          title: 'Fixed asset',
          detail: 'Assets are coming soon.',
        );
      case ResolvedType.blocked:
        return _Banner(
          key: const Key('scan_blocked'),
          icon: Icons.block,
          color: Theme.of(context).colorScheme.error,
          title: 'Not in your scope',
          detail: 'This code belongs to another organisation and can\'t be '
              'opened here.',
        );
      case ResolvedType.noMatch:
        return _Banner(
          key: const Key('scan_no_match'),
          icon: Icons.search_off,
          color: Theme.of(context).colorScheme.outline,
          title: 'No match',
          detail: 'Nothing matched "${result.rawCode ?? ''}". Check the code '
              'or enter it manually.',
        );
      case ResolvedType.unknown:
        return _Banner(
          key: const Key('scan_unknown'),
          icon: Icons.help_outline,
          color: Theme.of(context).colorScheme.outline,
          title: 'Unrecognized result',
          detail: 'This code couldn\'t be handled by this app version.',
        );
    }
  }
}

class _ManualEntry extends StatefulWidget {
  const _ManualEntry({required this.state});

  final ScannerState state;

  @override
  State<_ManualEntry> createState() => _ManualEntryState();
}

class _ManualEntryState extends State<_ManualEntry> {
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
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const Key('manual_code_field'),
              controller: _controller,
              decoration: const InputDecoration(
                labelText: 'Enter code manually',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => _submit(),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            key: const Key('manual_submit'),
            onPressed: widget.state.resolving ? null : _submit,
            child: const Text('Go'),
          ),
        ],
      ),
    );
  }
}

class _PermissionDenied extends StatelessWidget {
  const _PermissionDenied();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black87,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        key: const Key('scan_permission_denied'),
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.no_photography, color: Colors.white70, size: 56),
          const SizedBox(height: 16),
          const Text(
            'Camera access is off',
            style: TextStyle(color: Colors.white, fontSize: 18),
          ),
          const SizedBox(height: 8),
          const Text(
            'Enable the camera in Settings, or enter codes manually below.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(color: color)),
                const SizedBox(height: 4),
                Text(detail, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
