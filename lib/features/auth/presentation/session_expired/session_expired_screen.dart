import 'package:flutter/material.dart';

import '../../../../core/di/service_locator.dart';
import '../controller/auth_controller.dart';

/// F1 — Session Expired. Shown when the stored token is rejected by the API
/// (a 401 on an authenticated request). Prompts the user to re-authenticate;
/// acknowledging returns to the activation flow.
class SessionExpiredScreen extends StatelessWidget {
  const SessionExpiredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.lock_clock_outlined,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Session expired',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'For your security, you\'ve been signed out. '
                    'Please sign in again to continue.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 32),
                  FilledButton(
                    key: const Key('session_expired_reauth'),
                    onPressed: () =>
                        sl<AuthController>().acknowledgeSessionExpired(),
                    child: const Text('Sign in again'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
