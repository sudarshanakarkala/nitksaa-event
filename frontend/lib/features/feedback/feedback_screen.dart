import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../features/auth/services/auth_controller.dart';
import '../../routes/app_routes.dart';
import '../../shared/site_links.dart';
import '../../shared/widgets/site_page.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import 'data/feedback_api.dart';

/// Feedback form, matching the website's FeedbackPage
/// (website: pages/FeedbackPage.jsx). Same fields, limits, states and
/// contact address; areas are the events app's own.
class FeedbackScreen extends ConsumerStatefulWidget {
  const FeedbackScreen({super.key});

  @override
  ConsumerState<FeedbackScreen> createState() => _FeedbackScreenState();
}

enum _Status { idle, sending, done, error }

class _FeedbackScreenState extends ConsumerState<FeedbackScreen> {
  static const _maxLength = 2000;
  static const _minLength = 10;

  static const _areas = <String, String>{
    'events': 'Events list',
    'event_details': 'Event details',
    'registration': 'Registration / payment',
    'my_events': 'My Events / badge',
    'account': 'My Account / Sign-in',
    'general': 'General / Platform',
  };

  static const _types = <String, String>{
    'bug': 'Something is broken',
    'suggestion': 'Suggestion / feature request',
    'data': 'My data is wrong',
    'other': 'Other',
  };

  final _api = FeedbackApi();
  final _message = TextEditingController();
  String _area = 'general';
  String _type = 'bug';
  _Status _status = _Status.idle;

  @override
  void initState() {
    super.initState();
    _message.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _message.text.trim().length >= _minLength && _status == _Status.idle;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    final token = ref.read(authControllerProvider).session?.accessToken;
    if (token == null) return;
    setState(() => _status = _Status.sending);
    try {
      await _api.submit(
        accessToken: token,
        area: _area,
        category: _type,
        message: _message.text.trim(),
      );
      if (mounted) setState(() => _status = _Status.done);
    } catch (_) {
      // Website behaviour: show the email fallback and let the user retry.
      if (mounted) setState(() => _status = _Status.error);
    }
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final auth = ref.watch(authControllerProvider);

    Widget body;
    if (auth.isChecking) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (!auth.isAuthenticated) {
      body = _SignInPrompt(onSignIn: () => context.go(AppRoutes.login));
    } else if (_status == _Status.done) {
      body = _Success(onBack: _goBack);
    } else {
      body = _buildForm(p);
    }

    return Title(
      title: 'NITKSAA Events · Feedback',
      color: p.primary,
      child: SitePage(title: 'Send feedback', child: body),
    );
  }

  Widget _buildForm(AppPalette p) {
    final sending = _status == _Status.sending;
    final remaining = _maxLength - _message.text.length;
    final compact = MediaQuery.sizeOf(context).width < 600;

    final areaField = _Field(
      label: 'Area',
      child: DropdownButtonFormField<String>(
        initialValue: _area,
        isExpanded: true,
        dropdownColor: p.surface,
        items: [
          for (final e in _areas.entries)
            DropdownMenuItem(value: e.key, child: Text(e.value)),
        ],
        onChanged: sending ? null : (v) => setState(() => _area = v ?? _area),
      ),
    );

    final typeField = _Field(
      label: 'Type',
      child: DropdownButtonFormField<String>(
        initialValue: _type,
        isExpanded: true,
        dropdownColor: p.surface,
        items: [
          for (final e in _types.entries)
            DropdownMenuItem(value: e.key, child: Text(e.value)),
        ],
        onChanged: sending ? null : (v) => setState(() => _type = v ?? _type),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (compact) ...[
          areaField,
          const SizedBox(height: 20),
          typeField,
        ] else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: areaField),
              const SizedBox(width: 14),
              Expanded(child: typeField),
            ],
          ),
        const SizedBox(height: 20),
        _Field(
          label: 'Message',
          child: TextField(
            controller: _message,
            autofocus: true,
            enabled: !sending,
            minLines: 8,
            maxLines: 14,
            maxLength: _maxLength,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
              hintText:
                  'Tell us what you experienced or what you\'d like to see improved…',
              counterText: '',
            ),
          ),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '$remaining characters remaining',
            style: AppTextStyles.labelSmall.copyWith(
              fontWeight: FontWeight.w400,
              color: remaining < 100
                  ? p.primary
                  : p.textPrimary.withValues(alpha: 0.3),
            ),
          ),
        ),
        if (_status == _Status.error) ...[
          const SizedBox(height: 20),
          _ErrorBox(onRetry: () => setState(() => _status = _Status.idle)),
        ],
        const SizedBox(height: 20),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: sending ? null : _goBack,
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: _canSubmit ? _submit : null,
              child: sending
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: p.onPrimary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text('Sending…'),
                      ],
                    )
                  : const Text('Send feedback'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Website-style field: small uppercase muted label above the control.
class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label.toUpperCase(),
          style: AppTextStyles.labelMedium.copyWith(color: context.palette.textMuted),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final style = AppTextStyles.bodySmall.copyWith(color: p.error, height: 1.5);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: p.error.withValues(alpha: 0.07),
        border: Border.all(color: p.error.withValues(alpha: 0.18)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('Could not send — please email us at ', style: style),
          InkWell(
            onTap: () => launchUrl(Uri(
              scheme: 'mailto',
              path: SiteLinks.contactEmail,
              queryParameters: {'subject': 'NITKSAA Events feedback'},
            )),
            child: Text(
              SiteLinks.contactEmail,
              style: style.copyWith(decoration: TextDecoration.underline),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}

class _Success extends StatelessWidget {
  const _Success({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Center(
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: p.success.withValues(alpha: 0.1),
                border: Border.all(color: p.success.withValues(alpha: 0.22)),
              ),
              child: Icon(Icons.check, color: p.success, size: 24),
            ),
            const SizedBox(height: 12),
            Text(
              'Thanks — feedback received',
              style: AppTextStyles.bodyMedium.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: p.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "We'll look into it and follow up if needed.",
              style: AppTextStyles.bodySmall.copyWith(color: p.textMuted),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onBack, child: const Text('Go back')),
          ],
        ),
      ),
    );
  }
}

class _SignInPrompt extends StatelessWidget {
  const _SignInPrompt({required this.onSignIn});

  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Please sign in to send feedback, so we can follow up with you.',
          style: AppTextStyles.bodyMedium.copyWith(color: p.textSecondary),
        ),
        const SizedBox(height: 8),
        Text(
          'Can\'t sign in? Email us at ${SiteLinks.contactEmail}.',
          style: AppTextStyles.bodySmall.copyWith(color: p.textMuted),
        ),
        const SizedBox(height: 20),
        FilledButton(onPressed: onSignIn, child: const Text('Sign in')),
      ],
    );
  }
}
