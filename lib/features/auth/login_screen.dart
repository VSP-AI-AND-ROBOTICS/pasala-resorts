import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/current_resort.dart';
import '../../core/errors.dart';
import '../../core/router.dart';
import '../../core/theme/app_assets.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/failure_view.dart';
import '../../core/widgets/hero_backdrop.dart';
import '../../data/repositories/auth_repository.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.next});

  /// Where to go after signing in instead of the role's landing page. The
  /// router passes only values on `postSignInPaths`.
  final String? next;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final user = await ref
          .read(authRepositoryProvider)
          .signIn(_email.text.trim(), _password.text);
      final resort = await loadCurrentResortFor(user);
      final next = widget.next;
      if (mounted) {
        context.go(next != null && !user.isPlatformAdmin
            ? next
            : landingPathFor(user, resort));
      }
    } on BookingFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(FailureView.messageFor(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: HeroBackdrop(
        imageAsset: AppAssets.heroNightAerial,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Spacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: PasalaTokens.motionBase,
                curve: Curves.easeOut,
                builder: (context, value, child) => Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, (1 - value) * 24),
                    child: child,
                  ),
                ),
                child: Card(
                  color: scheme.surfaceContainerLow,
                  child: Padding(
                    padding: const EdgeInsets.all(Spacing.xl),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'ResortHub',
                            style: textTheme.headlineMedium,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: Spacing.xs),
                          Text(
                            'Welcome back',
                            style: textTheme.bodyLarge
                                ?.copyWith(color: scheme.onSurfaceVariant),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: Spacing.xl),
                          TextFormField(
                            key: const Key('login-email'),
                            controller: _email,
                            decoration: const InputDecoration(labelText: 'Email'),
                            keyboardType: TextInputType.emailAddress,
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Enter your email'
                                : null,
                          ),
                          const SizedBox(height: Spacing.sm),
                          TextFormField(
                            key: const Key('login-password'),
                            controller: _password,
                            decoration:
                                const InputDecoration(labelText: 'Password'),
                            obscureText: true,
                            validator: (v) => (v == null || v.isEmpty)
                                ? 'Enter your password'
                                : null,
                          ),
                          const SizedBox(height: Spacing.lg),
                          FilledButton(
                            onPressed: _busy ? null : _submit,
                            child: const Text('Sign in'),
                          ),
                          TextButton(
                            onPressed: () => context.go(widget.next == null
                                ? '/signup'
                                : '/signup?next=${Uri.encodeQueryComponent(widget.next!)}'),
                            child: const Text('Create an account'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
