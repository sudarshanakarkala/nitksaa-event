import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/api_error_message.dart';
import '../../routes/app_routes.dart';
import '../../routes/return_after_sign_in.dart';
import '../../shared/widgets/site_page.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../auth/services/auth_controller.dart';
import 'data/check_in_api.dart';

/// Opened from an entry pass QR (`/checkin/:eventId/:token`), usually by a
/// phone's camera. The event's admins (volunteers) see who it is and check
/// them in with one tap. Anyone else just sees that it's an entry pass:
/// the link on its own does nothing.
class CheckInScreen extends ConsumerStatefulWidget {
  const CheckInScreen({super.key, required this.eventId, required this.qrToken});

  final int eventId;
  final String qrToken;

  @override
  ConsumerState<CheckInScreen> createState() => _CheckInScreenState();
}

enum _Stage { idle, loading, loaded, checkingIn, checkedIn, failed }

class _CheckInScreenState extends ConsumerState<CheckInScreen> {
  _Stage _stage = _Stage.idle;
  EntryPassCheck? _pass;
  String? _error;

  /// The check-in made on this page, for Undo.
  CheckInDone? _done;

  /// The session the pass was looked up for; a new sign-in looks it up again.
  String? _loadedFor;

  bool _rememberedForSignIn = false;

  Future<void> _load(String accessToken) async {
    _loadedFor = accessToken;
    setState(() {
      _stage = _Stage.loading;
      _error = null;
    });
    try {
      final pass = await ref.read(checkInApiProvider).verify(
            eventId: widget.eventId,
            qrToken: widget.qrToken,
            accessToken: accessToken,
          );
      if (!mounted) return;
      setState(() {
        _pass = pass;
        _stage = _Stage.loaded;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = apiErrorMessage(e, action: 'check this pass');
        _stage = _Stage.failed;
      });
    }
  }

  Future<void> _checkIn(String accessToken) async {
    setState(() => _stage = _Stage.checkingIn);
    try {
      final done = await ref.read(checkInApiProvider).checkIn(
            eventId: widget.eventId,
            qrToken: widget.qrToken,
            accessToken: accessToken,
          );
      if (!mounted) return;
      setState(() {
        _done = done;
        _stage = _Stage.checkedIn;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      if (e.response?.statusCode == 409) {
        // Someone else checked them in a moment ago.
        await _load(accessToken);
        return;
      }
      setState(() {
        _error = apiErrorMessage(e, action: 'check in');
        _stage = _Stage.failed;
      });
    }
  }

  /// Undo a mistaken check-in made on this page.
  Future<void> _undo(String accessToken) async {
    final done = _done;
    if (done == null) return;
    setState(() => _stage = _Stage.checkingIn);
    try {
      await ref.read(checkInApiProvider).undo(
            eventId: widget.eventId,
            checkinId: done.checkinId,
            accessToken: accessToken,
          );
      if (!mounted) return;
      _done = null;
      await _load(accessToken);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = apiErrorMessage(e, action: 'undo the check-in');
        _stage = _Stage.failed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final token = auth.isAuthenticated ? auth.session?.accessToken : null;
    final canCheckIn =
        token != null && (auth.session?.access.canAdminEvent(widget.eventId) ?? false);

    // Signed out: remember this page, so signing in (even with an emailed
    // link opened in a new tab) comes back here.
    if (!auth.isChecking && token == null && !_rememberedForSignIn) {
      _rememberedForSignIn = true;
      ReturnAfterSignIn.save('/checkin/${widget.eventId}/${widget.qrToken}');
    }

    if (canCheckIn && _loadedFor != token) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _loadedFor != token) _load(token);
      });
    }

    final Widget body;
    if (auth.isChecking) {
      body = const _Centered(child: CircularProgressIndicator());
    } else if (!canCheckIn) {
      body = _EntryPassInfo(signedIn: token != null);
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _volunteerView(token),
          const SizedBox(height: 16),
          Center(
            child: TextButton.icon(
              onPressed: () => context.go('/admin/checkin?event=${widget.eventId}'),
              icon: const Icon(Icons.list_alt, size: 18),
              label: const Text('Check-in list for this event'),
            ),
          ),
        ],
      );
    }

    return SitePage(
      eyebrow: 'Entry pass',
      title: 'Check-in',
      maxContentWidth: 520,
      child: body,
    );
  }

  Widget _volunteerView(String accessToken) {
    final p = context.palette;
    switch (_stage) {
      case _Stage.idle:
      case _Stage.loading:
        return const _Centered(child: CircularProgressIndicator());
      case _Stage.failed:
        return _ResultCard(
          tone: p.error,
          icon: Icons.error_outline,
          headline: 'Something went wrong',
          detail: _error,
          action: OutlinedButton(
            onPressed: () => _load(accessToken),
            child: const Text('Try again'),
          ),
        );
      case _Stage.checkedIn:
        return _ResultCard(
          tone: p.success,
          icon: Icons.check_circle,
          name: _pass?.displayName,
          headline: 'Checked in',
          action: _done == null
              ? null
              : OutlinedButton(
                  onPressed: () => _undo(accessToken),
                  child: const Text('Undo'),
                ),
        );
      case _Stage.loaded:
      case _Stage.checkingIn:
        final pass = _pass!;
        if (pass.alreadyCheckedIn) {
          return _ResultCard(
            tone: p.warning,
            icon: Icons.info_outline,
            name: pass.displayName,
            headline: 'Already checked in',
          );
        }
        switch (pass.message) {
          case 'ready_to_checkin':
            return _ResultCard(
              tone: p.info,
              icon: Icons.badge_outlined,
              name: pass.displayName,
              headline: 'Registered',
              action: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                  ),
                  onPressed: _stage == _Stage.checkingIn ? null : () => _checkIn(accessToken),
                  child: Text(
                    _stage == _Stage.checkingIn ? 'Checking in…' : 'Check in',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            );
          case 'registration_not_eligible':
            return _ResultCard(
              tone: p.error,
              icon: Icons.block,
              name: pass.displayName,
              headline: 'Not registered',
              detail: 'This registration was cancelled or never paid.',
            );
          default:
            return _ResultCard(
              tone: p.error,
              icon: Icons.block,
              headline: 'Not a pass for this event',
              detail: 'This QR code isn\'t valid for this event.',
            );
        }
    }
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.symmetric(vertical: 48), child: Center(child: child));
}

/// One big, colour-coded answer a volunteer can read at a glance.
class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.tone,
    required this.icon,
    required this.headline,
    this.name,
    this.detail,
    this.action,
  });

  final Color tone;
  final IconData icon;
  final String headline;
  final String? name;
  final String? detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: p.tinted(tone, 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tone.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 48, color: tone),
          const SizedBox(height: 12),
          if (name != null && name!.trim().isNotEmpty) ...[
            Text(
              name!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppTextStyles.serif,
                fontSize: 26,
                fontWeight: FontWeight.w600,
                color: p.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
          ],
          Text(
            headline,
            textAlign: TextAlign.center,
            style: AppTextStyles.titleMedium.copyWith(color: tone, fontWeight: FontWeight.w700),
          ),
          if (detail != null) ...[
            const SizedBox(height: 8),
            Text(
              detail!,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(color: p.textSecondary),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: 20),
            action!,
          ],
        ],
      ),
    );
  }
}

/// What everyone but the event's admins sees.
class _EntryPassInfo extends StatelessWidget {
  const _EntryPassInfo({required this.signedIn});

  final bool signedIn;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ResultCard(
          tone: p.info,
          icon: Icons.qr_code_2,
          headline: 'This is an entry pass',
          detail: 'Show the QR code at the entrance to check in.',
        ),
        const SizedBox(height: 20),
        Text(
          signedIn
              ? 'Volunteers: you need to be an admin of this event to check people in.'
              : 'Volunteers: sign in, then scan the QR code again.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodySmall.copyWith(color: p.textMuted),
        ),
        if (!signedIn) ...[
          const SizedBox(height: 12),
          Center(
            child: OutlinedButton(
              onPressed: () => context.go(AppRoutes.login),
              child: const Text('Sign in'),
            ),
          ),
        ],
      ],
    );
  }
}
