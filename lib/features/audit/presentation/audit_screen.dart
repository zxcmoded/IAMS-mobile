import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/di/service_locator.dart';
import '../data/audit_file_service.dart';
import '../data/audit_import_parser.dart';
import '../data/audit_qty_format.dart';
import '../data/models/audit_record.dart';
import 'audit_cubit.dart';

/// The fully-offline **Audit** tab. Lets the user import a CSV/XLSX file of audit
/// rows (validated before anything is saved), export the stored rows, and
/// download a sample template. Everything is backed by local SQLite — there are
/// no API/network calls anywhere in this screen.
///
/// Route + class name are kept stable (`AuditScreen`, `/audit`) so the
/// bottom-navigation wiring in `app_router.dart` is unaffected.
class AuditScreen extends StatelessWidget {
  const AuditScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<AuditCubit>(
      create: (_) => sl<AuditCubit>()..load(),
      child: const _AuditView(),
    );
  }
}

class _AuditView extends StatelessWidget {
  const _AuditView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.green,
        title: const Text('Audit'),
        actions: [
          BlocBuilder<AuditCubit, AuditState>(
            buildWhen: (a, b) => a.records.length != b.records.length,
            builder: (context, state) {
              if (state.records.isEmpty) return const SizedBox.shrink();
              return IconButton(
                key: const Key('audit_clear'),
                tooltip: 'Clear all records',
                icon: const Icon(Icons.delete_sweep_outlined),
                onPressed: () => _confirmClear(context),
              );
            },
          ),
        ],
      ),
      body: BlocConsumer<AuditCubit, AuditState>(
        listenWhen: (a, b) =>
            a.actionMessage != b.actionMessage ||
            a.actionError != b.actionError ||
            (a.pendingImport == null && b.pendingImport != null),
        listener: (context, state) {
          final messenger = ScaffoldMessenger.of(context);
          if (state.actionError != null) {
            messenger
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(
                content: Text(state.actionError!),
                backgroundColor: Theme.of(context).colorScheme.error,
              ));
            context.read<AuditCubit>().acknowledgeMessages();
          } else if (state.actionMessage != null) {
            messenger
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text(state.actionMessage!)));
            context.read<AuditCubit>().acknowledgeMessages();
          }
          if (state.pendingImport != null) {
            _showImportReview(context, state.pendingImport!);
          }
        },
        builder: (context, state) {
          return SafeArea(
            child: Column(
              children: [
                _ActionBar(isBusy: state.isBusy),
                if (state.isBusy) const LinearProgressIndicator(minHeight: 2),
                const Divider(height: 1),
                Expanded(child: _RecordsSection(state: state)),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final cubit = context.read<AuditCubit>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all audit records?'),
        content: const Text(
            'This permanently removes every stored audit row from this device. '
            'This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) cubit.clearAll();
  }

  Future<void> _showImportReview(
      BuildContext context, AuditImportResult result) async {
    final cubit = context.read<AuditCubit>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _ImportReviewSheet(
        result: result,
        onCancel: () {
          Navigator.of(ctx).pop();
          cubit.cancelImport();
        },
        onConfirm: () {
          Navigator.of(ctx).pop();
          cubit.confirmImport();
        },
      ),
    );
  }
}

/// Import / Export / Template action row.
class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.isBusy});

  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<AuditCubit>();
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            key: const Key('audit_import'),
            onPressed: isBusy ? null : cubit.pickAndValidateImport,
            icon: const Icon(Icons.file_upload_outlined),
            label: const Text('Import'),
          ),
          OutlinedButton.icon(
            key: const Key('audit_export'),
            onPressed: isBusy
                ? null
                : () => _pickFormat(context, 'Export as', cubit.exportRecords),
            icon: const Icon(Icons.file_download_outlined),
            label: const Text('Export'),
          ),
          OutlinedButton.icon(
            key: const Key('audit_template'),
            onPressed: isBusy
                ? null
                : () => _pickFormat(
                    context, 'Download template as', cubit.downloadTemplate),
            icon: const Icon(Icons.description_outlined),
            label: const Text('Template'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickFormat(
    BuildContext context,
    String title,
    void Function(AuditFileFormat) onPicked,
  ) async {
    final choice = await showModalBottomSheet<AuditFileFormat>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(title, style: Theme.of(ctx).textTheme.titleMedium),
            ),
            ListTile(
              key: const Key('format_csv'),
              leading: const Icon(Icons.grid_on_outlined),
              title: const Text('CSV (.csv)'),
              onTap: () => Navigator.of(ctx).pop(AuditFileFormat.csv),
            ),
            ListTile(
              key: const Key('format_xlsx'),
              leading: const Icon(Icons.table_chart_outlined),
              title: const Text('Excel (.xlsx)'),
              onTap: () => Navigator.of(ctx).pop(AuditFileFormat.xlsx),
            ),
          ],
        ),
      ),
    );
    if (choice != null) onPicked(choice);
  }
}

/// The records list with explicit loading / error / empty / loaded states.
class _RecordsSection extends StatelessWidget {
  const _RecordsSection({required this.state});

  final AuditState state;

  @override
  Widget build(BuildContext context) {
    switch (state.status) {
      case AuditStatus.loading:
        return const Center(child: CircularProgressIndicator());
      case AuditStatus.error:
        return _ErrorState(
          message: state.errorMessage ?? 'Something went wrong.',
          onRetry: () => context.read<AuditCubit>().refresh(),
        );
      case AuditStatus.loaded:
        if (state.isEmpty) return const _EmptyState();
        return RefreshIndicator(
          onRefresh: () => context.read<AuditCubit>().refresh(),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${state.records.length} record(s)',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: state.records.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) =>
                      _RecordRow(record: state.records[i]),
                ),
              ),
            ],
          ),
        );
    }
  }
}

class _RecordRow extends StatelessWidget {
  const _RecordRow({required this.record});

  final AuditRecord record;

  @override
  Widget build(BuildContext context) {
    final location = [
      record.warehouse,
      if (record.rack != null && record.rack!.isNotEmpty) record.rack!,
      if (record.bin != null && record.bin!.isNotEmpty) record.bin!,
    ].join(' › ');
    return ListTile(
      key: Key('audit_row_${record.id}'),
      title: Text(record.sku, overflow: TextOverflow.ellipsis),
      subtitle: Text(location),
      trailing: Text(
        formatAuditQty(record.qty),
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}

/// Bottom sheet summarising a parsed import: how many rows are valid, and a
/// per-row breakdown of what failed. The confirm button imports only the valid
/// rows (disabled when there are none).
class _ImportReviewSheet extends StatelessWidget {
  const _ImportReviewSheet({
    required this.result,
    required this.onCancel,
    required this.onConfirm,
  });

  final AuditImportResult result;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Review import', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Row(
              children: [
                _Chip(
                  key: const Key('import_valid_count'),
                  icon: Icons.check_circle_outline,
                  color: Colors.green,
                  label: '${result.validCount} valid',
                ),
                const SizedBox(width: 8),
                _Chip(
                  key: const Key('import_error_count'),
                  icon: Icons.error_outline,
                  color: theme.colorScheme.error,
                  label: '${result.errorCount} with errors',
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (result.hasRowErrors) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Rows that will be skipped:',
                    style: theme.textTheme.titleSmall),
              ),
              const SizedBox(height: 4),
              Flexible(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.35,
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: result.rowErrors.length,
                    itemBuilder: (context, i) {
                      final err = result.rowErrors[i];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.warning_amber_outlined),
                        title: Text(err.summary),
                      );
                    },
                  ),
                ),
              ),
            ] else
              Text('All rows passed validation.',
                  style: theme.textTheme.bodyMedium),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  key: const Key('import_cancel'),
                  onPressed: onCancel,
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const Key('import_confirm'),
                  onPressed: result.hasValidRecords ? onConfirm : null,
                  child: Text('Import ${result.validCount} valid row(s)'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, color: color, size: 18),
      label: Text(label),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 96),
        Icon(Icons.fact_check_outlined,
            size: 56, color: Theme.of(context).colorScheme.outline),
        const SizedBox(height: 16),
        Text('No audit records yet',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'Import a CSV or Excel file to get started. Tap "Template" to '
            'download the expected format.',
            textAlign: TextAlign.center,
          ),
        ),
      ],
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
