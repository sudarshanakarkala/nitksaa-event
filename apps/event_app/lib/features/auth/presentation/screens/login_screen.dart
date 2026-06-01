import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/logger/app_logger.dart';
import '../../../../routes/app_routes.dart';
import '../../services/auth_controller.dart';
import '../../services/firebase_auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authController = AuthController.instance;
  bool _obscurePassword = true;
  bool _emailLoading = false;
  bool _googleLoading = false;
  String? _statusMessage;
  String? _errorMessage;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleEmailLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Enter both email and password.');
      return;
    }

    AppLogger.info('Email login attempt initiated');
    await _runLogin(
      loadingSetter: (loading) => _emailLoading = loading,
      login: () =>
          _authController.signInWithEmail(email: email, password: password),
    );
  }

  Future<void> _handleGoogleSignIn() async {
    AppLogger.info('Google Sign-In tapped');
    await _runLogin(
      loadingSetter: (loading) => _googleLoading = loading,
      login: _authController.signInWithGoogle,
    );
  }

  Future<void> _runLogin({
    required void Function(bool loading) loadingSetter,
    required Future<void> Function() login,
  }) async {
    if (_emailLoading || _googleLoading) return;

    setState(() {
      loadingSetter(true);
      _errorMessage = null;
      _statusMessage = 'Signing in with Firebase...';
    });

    try {
      await login();
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Backend session validated. Opening home...';
      });
      context.go(AppRoutes.home);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = _authController.errorMessage ?? _friendlyError(error);
        _statusMessage = null;
      });
    } finally {
      if (mounted) {
        setState(() => loadingSetter(false));
      }
    }
  }

  String _friendlyError(Object error) {
    final message = error.toString();
    if (message.startsWith('Exception: ')) {
      return message.substring('Exception: '.length);
    }
    return message;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Icon(
                      Icons.account_balance_outlined,
                      size: 56,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: Text(
                      'Welcome Back',
                      style: textTheme.headlineMedium,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: Text(
                      'Sign in to your NITKSAA account',
                      style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 36),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (_statusMessage != null || _errorMessage != null) ...[
                    _LoginStatusBanner(
                      message: _errorMessage ?? _statusMessage!,
                      isError: _errorMessage != null,
                    ),
                    const SizedBox(height: 16),
                  ],
                  FilledButton(
                    onPressed: (_emailLoading || _googleLoading)
                        ? null
                        : _handleEmailLogin,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _emailLoading
                        ? const _ButtonProgressLabel(label: 'Signing In')
                        : const Text('Sign In'),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'or',
                          style: textTheme.bodyMedium?.copyWith(
                            color: colorScheme.outline,
                          ),
                        ),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: (_emailLoading || _googleLoading)
                        ? null
                        : _handleGoogleSignIn,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: _googleLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.g_mobiledata, size: 22),
                    label: Text(
                      _googleLoading ? 'Validating...' : 'Continue with Google',
                    ),
                  ),
                  const SizedBox(height: 40),
                  Center(
                    child: Text(
                      'NITKSAA Event v1.0.0',
                      style: textTheme.labelSmall?.copyWith(
                        color: colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                  if (kDebugMode) ...[
                    const SizedBox(height: 8),
                    Center(
                      child: TextButton(
                        onPressed: () => context.go(AppRoutes.developer),
                        child: const Text('Developer Diagnostics'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginStatusBanner extends StatelessWidget {
  const _LoginStatusBanner({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final background = isError
        ? colorScheme.errorContainer
        : colorScheme.secondaryContainer;
    final foreground = isError
        ? colorScheme.onErrorContainer
        : colorScheme.onSecondaryContainer;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.verified_user_outlined,
              color: foreground,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ButtonProgressLabel extends StatelessWidget {
  const _ButtonProgressLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Theme.of(context).colorScheme.onPrimary,
          ),
        ),
        const SizedBox(width: 10),
        Text(label),
      ],
    );
  }
}
