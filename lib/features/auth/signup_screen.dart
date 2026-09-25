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

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key, this.next});

  /// Where to go after signing up instead of the role's landing page. The
  /// router passes only values on `postSignInPaths`.
  final String? next;

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final user = await ref.read(authRepositoryProvider).signUp(
            email: _email.text.trim(),
            password: _password.text,
            fullName: _name.text.trim(),
          );
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
                            'Create your account',
                            style: textTheme.bodyLarge
                                ?.copyWith(color: scheme.onSurfaceVariant),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: Spacing.xl),
                          TextFormField(
                            key: const Key('signup-name'),
                            controller: _name,
                            decoration:
                                const InputDecoration(labelText: 'Full name'),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Enter your name'
                                : null,
                          ),
                          const SizedBox(height: Spacing.sm),
                          TextFormField(
                            key: const Key('signup-email'),
                            controller: _email,
                            decoration: const InputDecoration(labelText: 'Email'),
                            keyboardType: TextInputType.emailAddress,
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Enter your email'
                                : null,
                          ),
                          const SizedBox(height: Spacing.sm),
                          TextFormField(
                            key: const Key('signup-password'),
                            controller: _password,
                            decoration:
                                const InputDecoration(labelText: 'Password'),
                            obscureText: true,
                            validator: (v) => (v == null || v.length < 8)
                                ? 'Use at least 8 characters'
                                : null,
                          ),
                          const SizedBox(height: Spacing.lg),
                          FilledButton(
                            onPressed: _busy ? null : _submit,
                            child: const Text('Create account'),
                          ),
                          TextButton(
                            onPressed: () => context.go(widget.next == null
                                ? '/login'
                                : '/login?next=${Uri.encodeQueryComponent(widget.next!)}'),
                            child:
                                const Text('Already have an account? Sign in'),
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
