import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

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
