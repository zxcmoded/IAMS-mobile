import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/service_locator.dart';
import '../controller/auth_controller.dart';
import 'activation_cubit.dart';

/// Activation Key entry — the sole authentication entry point now that
/// login/2FA are gone. One field, one button.
/// States: idle · activating · error (retryable) · terminal (contact admin).
class ActivationScreen extends StatelessWidget {
  const ActivationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ActivationCubit>(
      create: (_) => sl<ActivationCubit>(),
      child: const _ActivationView(),
    );
  }
}

class _ActivationView extends StatefulWidget {
  const _ActivationView();

  @override
  State<_ActivationView> createState() => _ActivationViewState();
}

class _ActivationViewState extends State<_ActivationView> {
  final _keyController = TextEditingController();

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    context.read<ActivationCubit>().submit(
          activationKey: _keyController.text,
        );
  }

  void _tryAgain() {
    _keyController.clear();
    context.read<ActivationCubit>().reset();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: BlocConsumer<ActivationCubit, ActivationState>(
          listenWhen: (prev, curr) =>
              curr.status == ActivationStatus.activated &&
              curr.session != null,
          listener: (context, state) {
            // Hand the session to the app-wide controller; the router
            // redirect then moves us into the authenticated area.
            sl<AuthController>().onAuthenticated(state.session!);
          },
          builder: (context, state) {
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'IAMS',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Enter Activation Key',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 32),
                      if (state.errorMessage != null)
                        _MessageBanner(message: state.errorMessage!),
                      TextField(
                        key: const Key('activation_key_field'),
                        controller: _keyController,
                        enabled: !state.isBusy && !state.isTerminal,
                        autofillHints: const [AutofillHints.oneTimeCode],
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: 'Activation Key',
                          border: const OutlineInputBorder(),
                          errorText: _firstFieldError(state, 'ActivationKey'),
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (state.isTerminal)
                        FilledButton(
                          key: const Key('activation_try_again'),
                          onPressed: _tryAgain,
                          child: const Text('Try again'),
                        )
                      else
                        FilledButton(
                          onPressed: state.isBusy ? null : _submit,
                          child: state.isBusy
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : const Text('Activate'),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  String? _firstFieldError(ActivationState state, String field) {
    final errors = state.fieldErrors[field];
    if (errors == null || errors.isEmpty) return null;
    return errors.first;
  }
}

class _MessageBanner extends StatelessWidget {
  const _MessageBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: scheme.onErrorContainer, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              key: const Key('activation_error_message'),
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
