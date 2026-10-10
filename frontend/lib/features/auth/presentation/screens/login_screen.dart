import 'package:flutter/cupertino.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/logger/app_logger.dart';
import 'package:go_router/go_router.dart';
import 'package:event_app/routes/app_routes.dart';
import '../../services/auth_controller.dart';
import '../../services/auth_error_messages.dart';
import 'package:event_app/widgets/material/app_scaffold.dart';
import 'package:event_app/widgets/material/app_primary_button.dart';


import 'package:event_app/theme/app_palette.dart';
import 'package:event_app/theme/app_text_styles.dart';
import 'package:event_app/shared/widgets/emblem_ring.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authController = AuthController.instance;
  bool _obscurePassword = true;
  bool _emailLoading = false;
  bool _googleLoading = false;
  String? _statusMessage;
  String? _errorMessage;

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
      login: () => _authController.signInWithEmail(email: email, password: password),
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
      _statusMessage = 'Signing in...';
    });
    try {
      await login();
      if (!mounted) return;
      setState(() => _statusMessage = 'Backend session validated. Opening home...');
      context.go(AppRoutes.home);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = _authController.errorMessage ?? genericSignInError;
        _statusMessage = null;
      });
    } finally {
      if (mounted) setState(() => loadingSetter(false));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Web (including Safari on iPhone) always uses the Material layout.
    final isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    return isIOS ? _buildCupertinoLogin() : _buildMaterialLogin();
  }

  // ---------------- Material UI (Android / Web) ----------------
  Widget _buildMaterialLogin() {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return AppScaffold(
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        title: const Text('Sign In'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: _LoginCard(
                children: _buildFormChildren(colorScheme, textTheme, false),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------- Cupertino UI (iOS) ----------------
  Widget _buildCupertinoLogin() {
    final bg = context.palette.background;
    return CupertinoPageScaffold(
      backgroundColor: bg,
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Sign In'),
      ),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: _LoginCard(
                children: _buildFormChildren(null, null, true),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Shared form widgets for both platforms
  List<Widget> _buildFormChildren(ColorScheme? colorScheme, TextTheme? textTheme, bool isCupertino) {
    final logo = Column(
      children: [
        const EmblemRing(size: 72),
        const SizedBox(height: 16),
        Text(
          'Sign in',
          style: AppTextStyles.headlineMedium.copyWith(color: context.palette.textPrimary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          'NITKSAA Events',
          style: AppTextStyles.bodyMedium.copyWith(color: context.palette.textSecondary),
          textAlign: TextAlign.center,
        ),
      ],
    );
    final emailField = isCupertino
        ? CupertinoTextField(
            controller: _emailController,
            placeholder: 'Email',
            keyboardType: TextInputType.emailAddress,
            prefix: const Padding(padding: EdgeInsets.only(left: 8), child: Icon(CupertinoIcons.mail)),
          )
        : TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.email_outlined),
              border: OutlineInputBorder(),
            ),
          );
    final passwordField = isCupertino
        ? CupertinoTextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            placeholder: 'Password',
            prefix: const Padding(padding: EdgeInsets.only(left: 8), child: Icon(CupertinoIcons.lock)),
            suffix: GestureDetector(
              onTap: () => setState(() => _obscurePassword = !_obscurePassword),
              child: Icon(_obscurePassword ? CupertinoIcons.eye : CupertinoIcons.eye_slash),
            ),
          )
        : TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
          );
    final loginButton = isCupertino
        ? CupertinoButton.filled(
            onPressed: (_emailLoading || _googleLoading) ? null : _handleEmailLogin,
            child: const Text('Sign In'),
          )
        : AppPrimaryButton(
            onPressed: (_emailLoading || _googleLoading) ? null : _handleEmailLogin,
            isLoading: _emailLoading,
            child: const Text('Sign In'),
          );
    final divider = Row(
      children: const [
        Expanded(child: Divider()),
        Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('or')),
        Expanded(child: Divider()),
      ],
    );
    final googleButton = isCupertino
        ? CupertinoButton(
            color: context.palette.surface,
            onPressed: (_emailLoading || _googleLoading) ? null : _handleGoogleSignIn,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(CupertinoIcons.cloud, color: context.palette.textPrimary),
              const SizedBox(width: 8),
              Text(_googleLoading ? 'Validating…' : 'Continue with Google')
            ]
          ),
        )
        : OutlinedButton.icon(
            onPressed: (_emailLoading || _googleLoading) ? null : _handleGoogleSignIn,
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            icon: _googleLoading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.g_mobiledata, size: 22),
            label: Text(_googleLoading ? 'Validating...' : 'Continue with Google'),
          );
    return [
      logo,
      const SizedBox(height: 28),
      googleButton,
      const SizedBox(height: 16),
      divider,
      const SizedBox(height: 16),
      emailField,
      const SizedBox(height: 16),
      passwordField,
      const SizedBox(height: 24),
      if (_statusMessage != null || _errorMessage != null) ...[
        _LoginStatusBanner(message: _errorMessage ?? _statusMessage!, isError: _errorMessage != null),
        const SizedBox(height: 16),
      ],
      loginButton,
      const SizedBox(height: 24),
      Center(
        child: Text(
          'NITKSAA Event v1.0.0',
          style: (textTheme?.labelSmall ?? Theme.of(context).textTheme.labelSmall ?? const TextStyle())
              .copyWith(color: colorScheme?.outline ?? Theme.of(context).colorScheme.outline),
        ),
      ),
    ];
  }
}

class _LoginStatusBanner extends StatelessWidget {
  const _LoginStatusBanner({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final background = isError ? colorScheme.errorContainer : colorScheme.secondaryContainer;
    final foreground = isError ? colorScheme.onErrorContainer : colorScheme.onSecondaryContainer;
    return DecoratedBox(
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(isError ? Icons.error_outline : Icons.verified_user_outlined, color: foreground, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(message, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: foreground, fontWeight: FontWeight.w600))),
          ],
        ),
      ),
    );
  }
}


/// Website login card: navy panel with a gold-tinted border.
class _LoginCard extends StatelessWidget {
  const _LoginCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}
