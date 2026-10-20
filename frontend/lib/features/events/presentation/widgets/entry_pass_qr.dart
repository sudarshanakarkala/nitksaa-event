import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../theme/app_palette.dart';
import '../../domain/my_event_registration.dart' show EntryPassInfo;

/// The link an entry pass QR holds. Any phone camera or Google Lens opens it;
/// an event admin who opens it gets the check-in page (`CheckInScreen`).
/// It uses the address the app is running on, so a beta QR opens beta.
String entryPassUrl(int eventId, String qrToken) {
  final base = Uri.base;
  final origin = base.scheme == 'http' || base.scheme == 'https'
      ? base.origin
      : 'https://events.nitkalumni.in'; // e.g. in tests
  return '$origin/#/checkin/$eventId/$qrToken';
}

/// An attendee's entry pass QR, drawn in the app (nothing is sent anywhere).
/// Always dark on white, whatever the theme, so every scanner can read it.
class EntryPassQr extends StatelessWidget {
  const EntryPassQr({
    super.key,
    required this.eventId,
    required this.qrToken,
    this.size = 200,
  });

  final int eventId;
  final String qrToken;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: QrImageView(
        data: entryPassUrl(eventId, qrToken),
        version: QrVersions.auto,
        size: size,
        padding: const EdgeInsets.all(12),
        backgroundColor: Colors.white,
        eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: Colors.black,
        ),
        semanticsLabel: 'Entry pass QR code',
      ),
    );
  }
}

/// Every entry pass in a registration (yours and your guests'), one under
/// the other, each with its name and number: shown at the door from My
/// Events. Each QR checks in only that person.
Future<void> showEntryPasses(
  BuildContext context, {
  required int eventId,
  required String eventTitle,
  required List<EntryPassInfo> passes,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) {
      final p = context.palette;
      return Dialog(
        backgroundColor: p.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        passes.length > 1 ? 'Your QR badges' : 'Your QR badge',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  eventTitle,
                  style: TextStyle(color: p.textSecondary),
                  textAlign: TextAlign.center,
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  child: Column(
                    children: [
                      for (final pass in passes) ...[
                        Text(
                          pass.name,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          textAlign: TextAlign.center,
                        ),
                        if (pass.guestOf != null)
                          Text(
                            'Guest of ${pass.guestOf}',
                            style: TextStyle(fontSize: 12, color: p.textSecondary),
                          ),
                        const SizedBox(height: 8),
                        EntryPassQr(eventId: eventId, qrToken: pass.qrToken),
                        if ((pass.number ?? '').isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Badge Number: ${pass.number}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ],
                        if (!identical(pass, passes.last)) const Divider(height: 32),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
