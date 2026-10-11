import 'dart:async';

import 'package:event_app/routes/app_routes.dart';
import 'package:event_app/shared/widgets/emblem_ring.dart';
import 'package:event_app/theme/app_palette.dart';
import 'package:event_app/theme/app_text_styles.dart';
import 'package:event_app/widgets/material/app_primary_button.dart';
import 'package:event_app/widgets/material/app_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/logger/app_logger.dart';
import '../../services/auth_controller.dart';
import '../../services/auth_error_messages.dart';

/// Sign-in, laid out like the website's login (website: pages/Login.jsx):
/// Continue with Google first, then an emailed sign-in link. Password
/// sign-in (kept for the admin-only accounts) is behind "Sign in with
/// password instead".
///
/// After a link is sent the card shows "Check your email" with Resend. A
/// link opened on a device that doesn't know the email lands here asking
/// for it (AuthController.pendingEmailLink).
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  static const _resendWait = 30;

  /// Google accounts sign in with Google, as on the website. Firebase can't
  /// tell us reliably (email-enumeration protection hides it), so Gmail
  /// addresses are steered by domain.
  static const _googleDomains = {'gmail.com', 'googlemail.com'};

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authController = AuthController.instance;

  bool _usePassword = false;
  bool _obscurePassword = true;
  bool _busy = false;
  bool _googleLoading = false;

  /// The address a link was sent to; non-null shows "Check your email".
  String? _sentTo;
  int _resendIn = 0;
  Timer? _resendTimer;

  String? _statusMessage;
  String? _errorMessage;

  @override
  void dispose() {
    _resendTimer?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  String? _checkEmail(String email) {
    if (email.isEmpty) return 'Enter your email address.';
    if (!email.contains('@') || !email.split('@').last.contains('.')) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  Future<void> _sendLink({bool resend = false}) async {
    final email = resend ? (_sentTo ?? '') : _emailController.text.trim();
    final problem = _checkEmail(email);
    if (problem != null) {
      setState(() => _errorMessage = problem);
      return;
    }
    if (_googleDomains.contains(email.split('@').last.toLowerCase())) {
      setState(() => _errorMessage =
          'This is a Google (Gmail) address. Use "Continue with Google" above.');
      return;
    }

    setState(() {
      _busy = true;
      _errorMessage = null;
      _statusMessage = null;
    });
    try {
      await _authController.sendSignInLink(email);
      if (!mounted) return;
      setState(() => _sentTo = email);
      _startResendCountdown();
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage =
          _authController.errorMessage ?? 'Could not send the sign-in link. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startResendCountdown() {
    _resendTimer?.cancel();
    setState(() => _resendIn = _resendWait);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _resendIn <= 1) timer.cancel();
      if (mounted) setState(() => _resendIn--);
    });
  }

  Future<void> _finishWithLink() async {
    final email = _emailController.text.trim();
    final problem = _checkEmail(email);
    if (problem != null) {
      setState(() => _errorMessage = problem);
      return;
    }
    await _runLogin(
      loadingSetter: (loading) => _busy = loading,
      login: () => _authController.completeEmailLinkSignIn(email: email),
    );
  }

  Future<void> _handlePasswordLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Enter both email and password.');
      return;
    }
    AppLogger.info('Email login attempt initiated');
    await _runLogin(
      loadingSetter: (loading) => _busy = loading,
      login: () => _authController.signInWithEmail(email: email, password: password),
    );
  }

  Future<void> _handleGoogleSignIn() async {
    AppLogger.info('Google Sign-In tapped');
    _authController.dismissEmailLink();
    await _runLogin(
      loadingSetter: (loading) => _googleLoading = loading,
      login: _authController.signInWithGoogle,
    );
  }

  Future<void> _runLogin({
    required void Function(bool loading) loadingSetter,
    required Future<void> Function() login,
  }) async {
    if (_busy || _googleLoading) return;
    setState(() {
      loadingSetter(true);
      _errorMessage = null;
      _statusMessage = 'Signing in...';
    });
    try {
      await login();
      if (!mounted) return;
      setState(() => _statusMessage = 'Signed in. Opening Events...');
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

  void _useDifferentEmail() {
    _resendTimer?.cancel();
    setState(() {
      _sentTo = null;
      _resendIn = 0;
      _errorMessage = null;
      _emailController.clear();
    });
  }

  void _cancelPendingLink() {
    _authController.dismissEmailLink();
    setState(() => _errorMessage = null);
  }

  // ── Layout ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final colorScheme = Theme.of(context).colorScheme;

    final List<Widget> body;
    if (auth.pendingEmailLink != null) {
      body = _confirmEmailView();
    } else if (_sentTo != null) {
      body = _checkEmailView();
    } else {
      body = _signInView();
    }

    // A link opened at startup that failed (expired, already used…).
    final notice = auth.pendingEmailLink == null ? auth.emailLinkNotice : null;
    final banner = _errorMessage ?? notice ?? _statusMessage;
    final bannerIsError = _errorMessage != null || notice != null;

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
                children: [
                  _logo(),
                  const SizedBox(height: 28),
                  ...body,
                  if (banner != null) ...[
                    const SizedBox(height: 16),
                    _LoginStatusBanner(message: banner, isError: bannerIsError),
                  ],
                  const SizedBox(height: 24),
                  Center(
                    child: Text(
                      'NITKSAA Event v1.0.0',
                      style: AppTextStyles.labelSmall.copyWith(color: colorScheme.outline),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _logo() {
    final p = context.palette;
    return Column(
      children: [
        const EmblemRing(size: 72),
        const SizedBox(height: 16),
        Text(
          'Sign in',
          style: AppTextStyles.headlineMedium.copyWith(color: p.textPrimary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          'NITKSAA Events',
          style: AppTextStyles.bodyMedium.copyWith(color: p.textSecondary),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _emailField({VoidCallback? onSubmitted}) => TextField(
        controller: _emailController,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        textInputAction: onSubmitted == null ? TextInputAction.next : TextInputAction.go,
        onSubmitted: onSubmitted == null ? null : (_) => onSubmitted(),
        decoration: const InputDecoration(
          labelText: 'Email',
          prefixIcon: Icon(Icons.email_outlined),
          border: OutlineInputBorder(),
        ),
      );

  List<Widget> _signInView() {
    final p = context.palette;
    final disabled = _busy || _googleLoading;
    return [
      OutlinedButton.icon(
        onPressed: disabled ? null : _handleGoogleSignIn,
        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
        icon: _googleLoading
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            // Google's "G", as on the website (Google sign-in branding).
            : Image.asset('assets/images/google-g.png', width: 18, height: 18),
        label: Text(_googleLoading ? 'Signing in...' : 'Continue with Google'),
      ),
      const SizedBox(height: 16),
      const Row(
        children: [
          Expanded(child: Divider()),
          Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('or')),
          Expanded(child: Divider()),
        ],
      ),
      const SizedBox(height: 16),
      Text(
        'Sign in with email',
        style: AppTextStyles.labelLarge.copyWith(color: p.textPrimary, letterSpacing: 0),
      ),
      const SizedBox(height: 10),
      _emailField(onSubmitted: _usePassword ? null : () => _sendLink()),
      if (_usePassword) ...[
        const SizedBox(height: 16),
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          autofillHints: const [AutofillHints.password],
          textInputAction: TextInputAction.go,
          onSubmitted: (_) => _handlePasswordLogin(),
          decoration: InputDecoration(
            labelText: 'Password',
            prefixIcon: const Icon(Icons.lock_outline),
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
        ),
        const SizedBox(height: 16),
        AppPrimaryButton(
          onPressed: disabled ? null : _handlePasswordLogin,
          isLoading: _busy,
          child: const Text('Sign In'),
        ),
      ] else ...[
        const SizedBox(height: 16),
        AppPrimaryButton(
          onPressed: disabled ? null : () => _sendLink(),
          isLoading: _busy,
          child: const Text('Send sign-in link'),
        ),
        const SizedBox(height: 8),
        Text(
          'We email you a link; no password needed. For Gmail and other '
          'Google accounts, use Continue with Google.',
          style: AppTextStyles.bodySmall.copyWith(color: p.textMuted),
        ),
      ],
      const SizedBox(height: 4),
      Align(
        child: TextButton(
          onPressed: disabled
              ? null
              : () => setState(() {
                    _usePassword = !_usePassword;
                    _errorMessage = null;
                  }),
          child: Text(_usePassword
              ? 'Email me a sign-in link instead'
              : 'Sign in with password instead'),
        ),
      ),
    ];
  }

  List<Widget> _checkEmailView() {
    final p = context.palette;
    return [
      Icon(Icons.mark_email_read_outlined, size: 44, color: p.primary),
      const SizedBox(height: 12),
      Text(
        'Check your email',
        textAlign: TextAlign.center,
        style: AppTextStyles.titleLarge.copyWith(color: p.textPrimary),
      ),
      const SizedBox(height: 8),
      Text.rich(
        TextSpan(
          children: [
            const TextSpan(text: 'We sent a sign-in link to '),
            TextSpan(
              text: _sentTo,
              style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w600),
            ),
            const TextSpan(
              text: '. Open it on this device to sign in. It works once and '
                  'expires after a while.',
            ),
          ],
        ),
        textAlign: TextAlign.center,
        style: AppTextStyles.bodyMedium.copyWith(color: p.textSecondary),
      ),
      const SizedBox(height: 6),
      Text(
        "Can't find it? Check your spam folder.",
        textAlign: TextAlign.center,
        style: AppTextStyles.bodySmall.copyWith(color: p.textMuted),
      ),
      const SizedBox(height: 20),
      OutlinedButton(
        onPressed: _busy || _resendIn > 0 ? null : () => _sendLink(resend: true),
        child: Text(_busy
            ? 'Sending...'
            : _resendIn > 0
            ? 'Resend in ${_resendIn}s'
            : 'Resend link'),
      ),
      const SizedBox(height: 4),
      TextButton(
        onPressed: _busy ? null : _useDifferentEmail,
        child: const Text('Use a different email'),
      ),
    ];
  }

  List<Widget> _confirmEmailView() {
    final p = context.palette;
    return [
      Text(
        'Finish signing in',
        textAlign: TextAlign.center,
        style: AppTextStyles.titleLarge.copyWith(color: p.textPrimary),
      ),
      const SizedBox(height: 8),
      Text(
        'Enter the email address the sign-in link was sent to.',
        textAlign: TextAlign.center,
        style: AppTextStyles.bodyMedium.copyWith(color: p.textSecondary),
      ),
      const SizedBox(height: 16),
      _emailField(onSubmitted: _finishWithLink),
      const SizedBox(height: 16),
      AppPrimaryButton(
        onPressed: _busy ? null : _finishWithLink,
        isLoading: _busy,
        child: const Text('Finish signing in'),
      ),
      const SizedBox(height: 4),
      TextButton(
        onPressed: _busy ? null : _cancelPendingLink,
        child: const Text('Cancel'),
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
            Expanded(
              child: Text(
                message,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: foreground, fontWeight: FontWeight.w600),
              ),
            ),
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
