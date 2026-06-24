class AlumniProfile {
  const AlumniProfile({
    required this.refId,
    required this.fullname,
    required this.email,
    required this.isActive,
    this.phone,
    this.batchYear,
    this.branch,
  });

  factory AlumniProfile.fromJson(Map<String, dynamic> json) {
    return AlumniProfile(
      refId: json['ref_id']?.toString() ?? '',
      fullname: json['fullname']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      phone: _str(json['phone']),
      batchYear: _int(json['batch_year']),
      branch: _str(json['branch']),
      isActive: json['is_active'] as bool? ?? false,
    );
  }

  final String refId;
  final String fullname;
  final String email;
  final String? phone;
  final int? batchYear;
  final String? branch;
  final bool isActive;
}

String? _str(dynamic v) {
  if (v is! String || v.trim().isEmpty) return null;
  return v.trim();
}

int? _int(dynamic v) => switch (v) {
      int n => n,
      num n => n.toInt(),
      String s => int.tryParse(s),
      _ => null,
    };
