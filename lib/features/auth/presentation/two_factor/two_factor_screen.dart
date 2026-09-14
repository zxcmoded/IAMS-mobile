import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/service_locator.dart';
import '../../data/auth_repository.dart';
import '../../data/models/auth_challenge.dart';
import '../controller/auth_controller.dart';
import 'two_factor_cubit.dart';

/// F1 — 2FA Challenge. OTP entry, resend (with cooldown), verify.
/// States: idle · verifying · error/retry · expired (restart login).
class TwoFactorScreen extends StatelessWidget {
  const TwoFactorScreen({super.key, required this.challenge});

  final AuthChallenge challenge;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<TwoFactorCubit>(
      create: (_) => TwoFactorCubit(sl<AuthRepository>(), challenge),
      child: const _TwoFactorView(),
    );
  }
}

class _TwoFactorView extends StatefulWidget {
  const _TwoFactorView();

  @override
  State<_TwoFactorView> createState() => _TwoFactorViewState();
}

class _TwoFactorViewState extends State<_TwoFactorView> {
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify it\'s you')),
      body: SafeArea(
        child: BlocConsumer<TwoFactorCubit, TwoFactorState>(
          listenWhen: (prev, curr) =>
              curr.status == TwoFactorStatus.verified && curr.session != null,
          listener: (context, state) {
            // Hand the session to the app-wide controller; the router redirect
            // then moves us into the authenticated area.
            sl<AuthController>().onAuthenticated(state.session!);
          },
          builder: (context, state) {
            final cubit = context.read<TwoFactorCubit>();
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
                        'Enter the 6-digit code',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'We sent a verification code to your registered device.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      // Defense-in-depth: the backend only sends devOtp in
                      // non-prod, but never render it in a release build even
                      // if a release build is ever pointed at a non-prod API.
                      if (!kReleaseMode && state.devOtp != null) ...[
                        const SizedBox(height: 12),
                        _DevOtpHint(otp: state.devOtp!),
                      ],
                      const SizedBox(height: 24),
                      if (state.errorMessage != null)
                        _MessageBanner(
                          message: state.errorMessage!,
                          isError: true,
                        ),
                      TextField(
                        controller: _codeController,
                        enabled: state.status != TwoFactorStatus.expired &&
                            !state.isVerifying,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 24, letterSpacing: 8),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          counterText: '',
                          border: OutlineInputBorder(),
                          hintText: '••••••',
                        ),
                        onSubmitted: (value) => cubit.verify(value),
                      ),
                      const SizedBox(height: 16),
                      if (state.status == TwoFactorStatus.expired)
                        FilledButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          child: const Text('Back to sign in'),
                        )
                      else
                        FilledButton(
                          onPressed: state.isVerifying
                              ? null
                              : () => cubit.verify(_codeController.text),
                          child: state.isVerifying
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : const Text('Verify'),
                        ),
                      const SizedBox(height: 8),
                      _ResendControl(
                        cooldown: state.resendCooldownSeconds,
                        canResend: state.canResend &&
                            state.status != TwoFactorStatus.expired,
                        isResending: state.isResending,
                        onResend: cubit.resend,
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
}

class _ResendControl extends StatelessWidget {
  const _ResendControl({
    required this.cooldown,
    required this.canResend,
    required this.isResending,
    required this.onResend,
  });

  final int cooldown;
  final bool canResend;
  final bool isResending;
  final VoidCallback onResend;

  @override
  Widget build(BuildContext context) {
    if (isResending) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(8),
          child: SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return TextButton(
      onPressed: canResend ? onResend : null,
      child: Text(
        cooldown > 0 ? 'Resend code in ${cooldown}s' : 'Resend code',
      ),
    );
  }
}

class _DevOtpHint extends StatelessWidget {
  const _DevOtpHint({required this.otp});

  final String otp;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.developer_mode,
              size: 18, color: scheme.onSecondaryContainer),
          const SizedBox(width: 8),
          Text(
            'Dev OTP: $otp',
            style: TextStyle(color: scheme.onSecondaryContainer),
          ),
        ],
      ),
    );
  }
}

class _MessageBanner extends StatelessWidget {
  const _MessageBanner({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = isError ? scheme.errorContainer : scheme.surfaceContainerHighest;
    final fg = isError ? scheme.onErrorContainer : scheme.onSurface;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        message,
        key: const Key('two_factor_message'),
        style: TextStyle(color: fg),
      ),
    );
  }
}
