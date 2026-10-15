import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/errors/api_error_message.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../auth/services/auth_controller.dart';
import 'data/check_in_api.dart';

/// Pulls the event id and token out of an entry pass QR
/// (`…/#/checkin/<event>/<token>`, see `entryPassUrl`).
({int eventId, String token})? parseEntryPass(String raw) {
  final m = RegExp(r'/checkin/(\d+)/([A-Za-z0-9_\-]+)').firstMatch(raw);
  if (m == null) return null;
  final id = int.tryParse(m.group(1)!);
  return id == null ? null : (eventId: id, token: m.group(2)!);
}

enum _Tone { success, warning, error, info }

/// The answer for the last QR seen.
class _Result {
  const _Result(this.tone, this.headline, {this.name, this.undo});

  final _Tone tone;
  final String headline;
  final String? name;

  /// The check-in this scan made, for Undo.
  final CheckInDone? undo;
}

/// Full-screen door scanner for one event: every valid entry pass the camera
/// sees is checked in straight away (green), with Undo for a mistake. Already
/// checked in is yellow; not registered or another event's pass is red.
/// The camera keeps running for the next person.
class CheckInScannerScreen extends ConsumerStatefulWidget {
  const CheckInScannerScreen({
    super.key,
    required this.eventId,
    required this.eventTitle,
    required this.total,
    required this.checkedIn,
  });

  final int eventId;
  final String eventTitle;
  final int total;
  final int checkedIn;

  @override
  ConsumerState<CheckInScannerScreen> createState() => _CheckInScannerScreenState();
}

class _CheckInScannerScreenState extends ConsumerState<CheckInScannerScreen> {
  /// The same QR is ignored for this long, so one pass isn't read twice.
  static const _repeatGap = Duration(seconds: 4);

  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.normal,
  );

  late int _checkedIn = widget.checkedIn;
  _Result? _result;
  bool _busy = false;
  String? _lastValue;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);

  String? get _token => ref.read(authControllerProvider).session?.accessToken;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    final raw = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
    if (raw == null || _busy) return;
    final now = DateTime.now();
    if (raw == _lastValue && now.difference(_lastAt) < _repeatGap) return;
    _lastValue = raw;
    _lastAt = now;
    _handle(raw);
  }

  Future<void> _handle(String raw) async {
    final pass = parseEntryPass(raw);
    if (pass == null) {
      _show(const _Result(_Tone.error, 'Not an entry pass'));
      return;
    }
    if (pass.eventId != widget.eventId) {
      _show(const _Result(_Tone.error, 'Pass for another event'));
      return;
    }
    final token = _token;
    if (token == null) return;

    setState(() => _busy = true);
    final api = ref.read(checkInApiProvider);
    try {
      final check = await api.verify(eventId: widget.eventId, qrToken: pass.token, accessToken: token);
      if (!mounted) return;
      if (check.alreadyCheckedIn) {
        _show(_Result(_Tone.warning, 'Already checked in', name: check.displayName));
      } else if (check.message == 'ready_to_checkin') {
        final done = await api.checkIn(eventId: widget.eventId, qrToken: pass.token, accessToken: token);
        if (!mounted) return;
        _checkedIn++;
        _show(_Result(_Tone.success, 'Checked in', name: check.displayName, undo: done));
      } else if (check.message == 'registration_not_eligible') {
        _show(_Result(_Tone.error, 'Not registered', name: check.displayName));
      } else {
        _show(const _Result(_Tone.error, 'Not a pass for this event'));
      }
    } catch (error) {
      if (!mounted) return;
      // Let the same QR be tried again straight away.
      _lastValue = null;
      _show(_Result(_Tone.error, apiErrorMessage(error, action: 'check in')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _show(_Result result) => setState(() => _result = result);

  Future<void> _undo(_Result result) async {
    final done = result.undo;
    final token = _token;
    if (done == null || token == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(checkInApiProvider).undo(
            eventId: widget.eventId,
            checkinId: done.checkinId,
            accessToken: token,
          );
      if (!mounted) return;
      _checkedIn--;
      // The same QR can be scanned again right away.
      _lastValue = null;
      _show(_Result(_Tone.info, 'Check-in undone', name: result.name));
    } catch (error) {
      if (!mounted) return;
      _show(_Result(_Tone.error, apiErrorMessage(error, action: 'undo the check-in')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Color _color(AppPalette p, _Tone tone) => switch (tone) {
        _Tone.success => p.success,
        _Tone.warning => p.warning,
        _Tone.error => p.error,
        _Tone.info => p.info,
      };

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final result = _result;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _CameraProblem(error: error),
          ),
          // Aim here.
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: result == null ? Colors.white70 : _color(p, result.tone),
                  width: 3,
                ),
              ),
            ),
          ),
          // Top: event, count, Done.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.black54,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.eventTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.titleMedium.copyWith(color: Colors.white),
                            ),
                            Text(
                              '$_checkedIn of ${widget.total} checked in',
                              style: AppTextStyles.bodySmall.copyWith(color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(foregroundColor: Colors.white),
                        child: const Text('Done'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Bottom: the answer for the last QR.
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: SafeArea(
              top: false,
              child: result == null
                  ? _Panel(
                      tone: Colors.white70,
                      background: Colors.black87,
                      headline: 'Point the camera at an entry pass',
                      busy: _busy,
                    )
                  : _Panel(
                      tone: _color(p, result.tone),
                      background: p.card,
                      headline: result.headline,
                      name: result.name,
                      busy: _busy,
                      action: result.undo != null
                          ? OutlinedButton(
                              onPressed: _busy ? null : () => _undo(result),
                              child: const Text('Undo'),
                            )
                          : null,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.tone,
    required this.background,
    required this.headline,
    required this.busy,
    this.name,
    this.action,
  });

  final Color tone;
  final Color background;
  final String headline;
  final String? name;
  final bool busy;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: tone, width: 6)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (name != null && name!.trim().isNotEmpty)
                  Text(
                    name!,
                    style: TextStyle(
                      fontFamily: AppTextStyles.serif,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: p.textPrimary,
                    ),
                  ),
                Text(
                  headline,
                  style: AppTextStyles.titleMedium.copyWith(color: tone, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          if (busy)
            const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
          else if (action != null)
            action!,
        ],
      ),
    );
  }
}

/// No camera, or camera permission refused.
class _CameraProblem extends StatelessWidget {
  const _CameraProblem({required this.error});

  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          denied
              ? 'Camera access is blocked. Allow the camera for this site in the browser settings, then open the scanner again.'
              : 'The camera couldn\'t start. Use the phone\'s own camera app to scan, or the Check-in list.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyMedium.copyWith(color: Colors.white),
        ),
      ),
    );
  }
}
