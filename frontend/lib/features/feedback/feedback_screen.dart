import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/errors/api_error_message.dart';
import '../../features/auth/services/auth_controller.dart';
import '../../routes/app_routes.dart';
import '../../shared/site_links.dart';
import '../../shared/widgets/form_fields.dart';
import '../../shared/widgets/site_page.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import 'data/attachment_picker.dart';
import 'data/feedback_api.dart';
import 'data/feedback_attachment.dart';

/// Feedback form, matching the website's FeedbackPage
/// (website: pages/FeedbackPage.jsx). Same fields, limits, states and
/// contact address; areas are the events app's own.
///
/// Up to 3 screenshots or short recordings (15 MB in total) can be attached;
/// they go on the feedback email only.
class FeedbackScreen extends ConsumerStatefulWidget {
  const FeedbackScreen({super.key, this.api, this.picker});

  /// For tests; the app uses the real ones.
  final FeedbackApi? api;
  final AttachmentPicker? picker;

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

  late final _api = widget.api ?? FeedbackApi();
  late final _picker = widget.picker ?? const AttachmentPicker();
  final _message = TextEditingController();
  String _area = 'general';
  String _type = 'bug';
  _Status _status = _Status.idle;

  final _files = <FeedbackAttachment>[];
  bool _reading = false;

  /// A plain-words problem with the files (too big, wrong type…), from the
  /// form's own checks or the server's refusal. Not the "email us" box.
  String? _fileMessage;

  /// Upload progress, 0–1, while sending with files.
  double? _progress;

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
      _message.text.trim().length >= _minLength &&
      _status == _Status.idle &&
      !_reading;

  Future<void> _attach() async {
    final picked = await _picker.pick();
    if (!mounted || picked.isEmpty) return;
    final check = checkPickedFiles(_files, picked);
    setState(() {
      _fileMessage = check.message;
      _reading = check.accepted.isNotEmpty;
    });
    for (final file in check.accepted) {
      try {
        final bytes = await file.read();
        if (!mounted) return;
        setState(() => _files.add(FeedbackAttachment(
              name: file.name,
              mimeType: file.mimeType,
              bytes: bytes,
            )));
      } catch (_) {
        if (mounted) setState(() => _fileMessage ??= attachmentUnreadableMessage);
      }
    }
    if (mounted) setState(() => _reading = false);
  }

  void _remove(FeedbackAttachment file) => setState(() {
        _files.remove(file);
        _fileMessage = null;
      });

  /// The server's or Cloud Run's refusal of the files, in plain words.
  String? _refusedFiles(Object error) {
    if (error is! DioException) return null;
    final status = error.response?.statusCode;
    if (status == 413) return attachmentTooLargeMessage;
    final detail = error.response?.data is Map
        ? (error.response!.data as Map)['detail']
        : null;
    if (status == 400 && detail is String && detail.contains('attachment')) {
      return apiErrorMessage(error, action: 'send feedback');
    }
    return null;
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    final token = ref.read(authControllerProvider).session?.accessToken;
    if (token == null) return;
    final withFiles = _files.isNotEmpty;
    setState(() {
      _status = _Status.sending;
      _fileMessage = null;
      _progress = withFiles ? 0 : null;
    });
    try {
      await _api.submit(
        accessToken: token,
        area: _area,
        category: _type,
        message: _message.text.trim(),
        attachments: List.of(_files),
        onSendProgress: (sent, total) {
          if (!mounted || total <= 0) return;
          setState(() => _progress = (sent / total).clamp(0.0, 1.0));
        },
      );
      if (mounted) setState(() => _status = _Status.done);
    } catch (e) {
      if (!mounted) return;
      final refused = _refusedFiles(e);
      setState(() {
        _progress = null;
        if (refused != null) {
          // Fixable here: say what's wrong with the files, keep everything.
          _fileMessage = refused;
          _status = _Status.idle;
        } else {
          // Website behaviour: show the email fallback and let the user
          // retry. The message and files stay on the form.
          _status = _Status.error;
        }
      });
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

    final areaField = LabeledField(
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

    final typeField = LabeledField(
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
        LabeledField(
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
        const SizedBox(height: 16),
        _Attachments(
          files: _files,
          enabled: !sending && !_reading,
          reading: _reading,
          message: _fileMessage,
          onAttach: _attach,
          onRemove: _remove,
        ),
        if (sending && _progress != null) ...[
          const SizedBox(height: 20),
          _UploadProgress(value: _progress!),
        ],
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

/// The Attach button, the chosen files (name, size, ✕) and any problem with
/// them.
class _Attachments extends StatelessWidget {
  const _Attachments({
    required this.files,
    required this.enabled,
    required this.reading,
    required this.message,
    required this.onAttach,
    required this.onRemove,
  });

  final List<FeedbackAttachment> files;
  final bool enabled;
  final bool reading;
  final String? message;
  final VoidCallback onAttach;
  final ValueChanged<FeedbackAttachment> onRemove;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final full = files.length >= maxFeedbackAttachments;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final file in files)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              key: ObjectKey(file),
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
              decoration: BoxDecoration(
                border: Border.all(color: p.textPrimary.withValues(alpha: 0.12)),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(
                    file.isVideo ? Icons.videocam_outlined : Icons.image_outlined,
                    size: 18,
                    color: p.textMuted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      file.name,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySmall.copyWith(color: p.textPrimary),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    formatFileSize(file.size),
                    style: AppTextStyles.bodySmall.copyWith(color: p.textMuted),
                  ),
                  IconButton(
                    tooltip: 'Remove ${file.name}',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: enabled ? () => onRemove(file) : null,
                  ),
                ],
              ),
            ),
          ),
        if (!full)
          OutlinedButton.icon(
            key: const ValueKey('feedback-attach'),
            onPressed: enabled ? onAttach : null,
            icon: reading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.attach_file, size: 18),
            label: Text(files.isEmpty
                ? 'Attach screenshots or a video'
                : 'Attach another file'),
          ),
        const SizedBox(height: 6),
        Text(
          'Optional. Up to 3 images or short videos (under a minute), '
          '15 MB in total.',
          style: AppTextStyles.labelSmall.copyWith(
            fontWeight: FontWeight.w400,
            color: p.textMuted,
          ),
        ),
        if (message != null) ...[
          const SizedBox(height: 8),
          Text(
            message!,
            key: const ValueKey('feedback-file-message'),
            style: AppTextStyles.bodySmall.copyWith(color: p.error),
          ),
        ],
      ],
    );
  }
}

/// "Sending… 45%" with a bar, while files upload.
class _UploadProgress extends StatelessWidget {
  const _UploadProgress({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final percent = (value * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LinearProgressIndicator(value: value, minHeight: 6),
        const SizedBox(height: 6),
        Text(
          percent >= 100 ? 'Sending… almost done' : 'Sending… $percent%',
          key: const ValueKey('feedback-progress'),
          style: AppTextStyles.bodySmall.copyWith(color: p.textMuted),
        ),
      ],
    );
  }
}

/// Website-style field: small uppercase muted label above the control.
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
