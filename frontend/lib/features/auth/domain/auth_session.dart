class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.firebaseUid,
    required this.userType,
    this.email,
    this.fullname,
    this.refId,
    this.graduationYear,
  });

  final String accessToken;
  final String firebaseUid;
  final String userType;
  final String? email;
  final String? fullname;
  final String? refId;
  final int? graduationYear;

  bool get isValid => accessToken.isNotEmpty && firebaseUid.isNotEmpty;

  AuthSession copyWith({
    String? accessToken,
    String? firebaseUid,
    String? userType,
    String? email,
    String? fullname,
    String? refId,
    int? graduationYear,
  }) {
    return AuthSession(
      accessToken: accessToken ?? this.accessToken,
      firebaseUid: firebaseUid ?? this.firebaseUid,
      userType: userType ?? this.userType,
      email: email ?? this.email,
      fullname: fullname ?? this.fullname,
      refId: refId ?? this.refId,
      graduationYear: graduationYear ?? this.graduationYear,
    );
  }

  factory AuthSession.fromBackendLogin(Map<String, dynamic> json) {
    return AuthSession(
      accessToken: json['access_token']?.toString() ?? '',
      firebaseUid: json['firebase_uid']?.toString() ?? '',
      userType: json['user_type']?.toString() ?? '',
      fullname: json['fullname']?.toString(),
      refId: json['ref_id']?.toString(),
      graduationYear: _intOrNull(json['graduation_year']),
    );
  }

  factory AuthSession.fromMeResponse({
    required String accessToken,
    required Map<String, dynamic> json,
  }) {
    return AuthSession(
      accessToken: accessToken,
      firebaseUid: json['firebase_uid']?.toString() ?? '',
      email: json['email']?.toString(),
      fullname: json['fullname']?.toString(),
      userType: json['user_type']?.toString() ?? '',
      refId: json['ref_id']?.toString(),
      graduationYear: _intOrNull(json['graduation_year']),
    );
  }

  factory AuthSession.fromStoredMap(Map<dynamic, dynamic> map) {
    return AuthSession(
      accessToken: map['access_token']?.toString() ?? '',
      firebaseUid: map['firebase_uid']?.toString() ?? '',
      email: map['email']?.toString(),
      fullname: map['fullname']?.toString(),
      userType: map['user_type']?.toString() ?? '',
      refId: map['ref_id']?.toString(),
      graduationYear: _intOrNull(map['graduation_year']),
    );
  }

  Map<String, dynamic> toStoredMap() {
    return {
      'access_token': accessToken,
      'firebase_uid': firebaseUid,
      'email': email,
      'fullname': fullname,
      'user_type': userType,
      'ref_id': refId,
      'graduation_year': graduationYear,
    };
  }

  static int? _intOrNull(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(value.toString());
  }
}
