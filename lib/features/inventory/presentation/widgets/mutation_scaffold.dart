import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../shared/mutation_args.dart';
import '../shared/mutation_outcome_banner.dart';
import '../shared/mutation_state.dart';

/// Shared chrome for the four F4 mutation forms: an item header, the caller's
/// [fields], a client-side validation message, the submit button (spinner while
/// submitting), and — once submitted — the inline [MutationOutcomeBanner] with a
/// "Back to item" affordance. Keeps every mutation screen visually and
/// behaviourally consistent.
class MutationScaffold extends StatelessWidget {
  const MutationScaffold({
    super.key,
    required this.title,
    required this.args,
    required this.state,
    required this.fields,
    required this.onSubmit,
    required this.submitLabel,
  });

  final String title;
  final MutationArgs args;
  final MutationState state;
  final List<Widget> fields;
  final VoidCallback onSubmit;
  final String submitLabel;

  @override
  Widget build(BuildContext context) {
    final done = state.isDone && state.result != null;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _ItemHeader(args: args),
            const SizedBox(height: 24),
            if (done) ...[
              MutationOutcomeBanner(result: state.result!),
              const SizedBox(height: 16),
              FilledButton.tonal(
                key: const Key('mutation_back'),
                onPressed: () => context.pop(),
                child: const Text('Back to item'),
              ),
            ] else ...[
              ...fields,
              if (state.validationMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  state.validationMessage!,
                  key: const Key('mutation_validation'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                key: const Key('mutation_submit'),
                onPressed: state.isSubmitting ? null : onSubmit,
                child: state.isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(submitLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ItemHeader extends StatelessWidget {
  const _ItemHeader({required this.args});

  final MutationArgs args;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.inventory_2_outlined),
        title: Text(args.name),
        subtitle: Text('SKU ${args.sku}'),
      ),
    );
  }
}
