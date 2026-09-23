import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/user_profile.dart';
import '../../core/services/mock_data_store.dart';
import '../../core/theme/app_theme.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Please enter your registered email and password.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    await Future.delayed(const Duration(milliseconds: 500));

    final store = MockDataStore.instance;
    final user = store.authenticate(email, password);

    setState(() => _isLoading = false);

    if (user == null) {
      setState(() => _errorMessage = 'Invalid email or password. Please check your credentials.');
      return;
    }

    if (!mounted) return;
    switch (user.role) {
      case AppRole.superAdmin:
        context.go('/super-admin');
        break;
      case AppRole.admin:
        context.go('/admin');
        break;
      case AppRole.incharge:
        context.go('/incharge');
        break;
      case AppRole.accountant:
        context.go('/accountant');
        break;
      case AppRole.customer:
        context.go('/customer');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final pageBg = AppTheme.pageBg(context);
    final cardBg = AppTheme.cardBg(context);
    final border = AppTheme.border(context);
    final textPrimary = AppTheme.textPrimary(context);
    final textMuted = AppTheme.textMuted(context);

    return Scaffold(
      backgroundColor: pageBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: border),
                boxShadow: [
                  BoxShadow(
                    color: isDark ? Colors.black.withValues(alpha: 0.3) : const Color(0xFF1C1917).withValues(alpha: 0.06),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // App Brand Logo: ResortHub
                  Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF5A36),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.apartment_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'ResortHub',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              color: textPrimary,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Sign in to manage or book your stays',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: textMuted, fontSize: 13),
                  ),
                  const SizedBox(height: 28),

                  // Email Input
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    style: TextStyle(fontSize: 14, color: textPrimary),
                    decoration: InputDecoration(
                      labelText: 'Email Address',
                      prefixIcon: Icon(Icons.email_outlined, size: 20, color: textMuted),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Password Input
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _handleLogin(),
                    style: TextStyle(fontSize: 14, color: textPrimary),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: Icon(Icons.lock_outline, size: 20, color: textMuted),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20, color: textMuted),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),

                  // Error Display
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: Colors.red.shade700, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: TextStyle(color: Colors.red.shade700, fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // Primary Action Button
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _handleLogin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF5A36),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Text('Sign in', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Center(
                    child: TextButton(
                      onPressed: () => context.go('/register'),
                      child: const Text(
                        "Don't have an account? Create an account",
                        style: TextStyle(color: Color(0xFFFF5A36), fontSize: 14, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Divider(color: border),
                  const SizedBox(height: 8),
                  Text(
                    'Quick Demo Logins:',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textMuted),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      ActionChip(
                        avatar: Icon(Icons.public, size: 14, color: textPrimary),
                        label: Text('All Resorts Accountant', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textPrimary)),
                        backgroundColor: AppTheme.pillBg(context),
                        side: BorderSide(color: border),
                        onPressed: () {
                          setState(() {
                            _emailController.text = 'accountant@resorthub.com';
                            _passwordController.text = 'password123';
                            _errorMessage = null;
                          });
                        },
                      ),
                      ActionChip(
                        avatar: Icon(Icons.lock, size: 14, color: textMuted),
                        label: Text('Grand Palms Accountant', style: TextStyle(fontSize: 11, color: textPrimary)),
                        backgroundColor: AppTheme.pillBg(context),
                        side: BorderSide(color: border),
                        onPressed: () {
                          setState(() {
                            _emailController.text = 'accountant@grandpalms.com';
                            _passwordController.text = 'password123';
                            _errorMessage = null;
                          });
                        },
                      ),
                      ActionChip(
                        label: Text('Resort Admin', style: TextStyle(fontSize: 11, color: textPrimary)),
                        backgroundColor: AppTheme.pillBg(context),
                        side: BorderSide(color: border),
                        onPressed: () {
                          setState(() {
                            _emailController.text = 'admin@grandpalms.com';
                            _passwordController.text = 'password123';
                            _errorMessage = null;
                          });
                        },
                      ),
                      ActionChip(
                        label: Text('Super Admin', style: TextStyle(fontSize: 11, color: textPrimary)),
                        backgroundColor: AppTheme.pillBg(context),
                        side: BorderSide(color: border),
                        onPressed: () {
                          setState(() {
                            _emailController.text = 'owner@resorthub.com';
                            _passwordController.text = 'password123';
                            _errorMessage = null;
                          });
                        },
                      ),
                    ],
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
