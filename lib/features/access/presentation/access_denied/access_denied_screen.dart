import 'package:flutter/material.dart';

/// Navigation args for the Access Denied screen. Both fields are optional so a
/// caller can show a generic denial or override the copy for a specific case
/// (e.g. a `403 access_denied` on an out-of-scope resource).
class AccessDeniedArgs {
  const AccessDeniedArgs({this.title, this.message});

  final String? title;
  final String? message;
}

/// A generic Access Denied screen: the server enforces Company + assigned-
/// Location scope, so a resource outside the caller's scope comes back as
/// `403 access_denied`. This screen explains that and offers a way back — it is
/// not tied to any cross-company connection concept.
class AccessDeniedScreen extends StatelessWidget {
  const AccessDeniedScreen({super.key, this.args});

  final AccessDeniedArgs? args;

  static const _defaultMessage =
      "You don't have access to this resource. It may be outside your "
      'company or your assigned locations. Contact your administrator if you '
      'think this is a mistake.';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Access denied')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 24),
          Icon(Icons.block, size: 64, color: scheme.error),
          const SizedBox(height: 16),
          Text(
            args?.title ?? 'Access denied',
            key: const Key('access_denied_title'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            args?.message ?? _defaultMessage,
            key: const Key('access_denied_message'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.arrow_back),
            label: const Text('Return'),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}
