import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/service_locator.dart';
import '../controller/auth_controller.dart';
import 'activation_cubit.dart';

/// Activation Key entry — the sole authentication entry point now that
/// login/2FA are gone.
///
/// On mount it asks the cubit to load any remembered key: if this device was
/// activated before, the user sees a one-tap "Welcome back" resume state
/// instead of the blank form; otherwise they type the key as usual.
/// States: resume · idle · activating · error (retryable) · terminal.
class ActivationScreen extends StatelessWidget {
  const ActivationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ActivationCubit>(
      create: (_) => sl<ActivationCubit>()..loadRemembered(),
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
                  child: state.isResume
                      ? _ResumeBody(isBusy: state.isBusy)
                      : _EntryBody(
                          state: state,
                          keyController: _keyController,
                          onSubmit: _submit,
                          onTryAgain: _tryAgain,
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// "Welcome back" resume state: one tap to continue with the remembered key,
/// or fall back to manual entry with a different key.
class _ResumeBody extends StatelessWidget {
  const _ResumeBody({required this.isBusy});

  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ActivationCubit>();
    return Column(
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
          'Welcome back',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'This device is already activated. Tap continue to sign back in.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 32),
        FilledButton(
          key: const Key('activation_resume_continue'),
          onPressed: isBusy ? null : cubit.resume,
          child: isBusy
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Continue'),
        ),
        const SizedBox(height: 12),
        TextButton(
          key: const Key('activation_use_different_key'),
          onPressed: isBusy ? null : cubit.useDifferentKey,
          child: const Text('Use a different activation key'),
        ),
      ],
    );
  }
}

/// Blank / error / terminal manual-entry form — one field, one button.
class _EntryBody extends StatelessWidget {
  const _EntryBody({
    required this.state,
    required this.keyController,
    required this.onSubmit,
    required this.onTryAgain,
  });

  final ActivationState state;
  final TextEditingController keyController;
  final VoidCallback onSubmit;
  final VoidCallback onTryAgain;

  @override
  Widget build(BuildContext context) {
    return Column(
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
          controller: keyController,
          enabled: !state.isBusy && !state.isTerminal,
          autofillHints: const [AutofillHints.oneTimeCode],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => onSubmit(),
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
            onPressed: onTryAgain,
            child: const Text('Try again'),
          )
        else
          FilledButton(
            onPressed: state.isBusy ? null : onSubmit,
            child: state.isBusy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Activate'),
          ),
      ],
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
