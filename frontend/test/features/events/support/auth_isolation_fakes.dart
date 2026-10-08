import 'dart:async';

import 'package:dio/dio.dart';
import 'package:event_app/features/auth/domain/auth_session.dart';
import 'package:event_app/features/auth/services/auth_controller.dart';
import 'package:event_app/features/events/data/events_repository.dart';
import 'package:event_app/features/events/domain/event.dart';
import 'package:flutter/foundation.dart';

/// Event id shared by every user in these tests. ISSUE-001 is about one
/// `eventDetailProvider(eventId)` instance outliving the user it was loaded
/// for, so both users must open the same id.
const eventX = 7;

const tokenA = 'token-A';
const tokenB = 'token-B';

const sessionA = AuthSession(
  accessToken: tokenA,
  firebaseUid: 'uid-A',
  userType: 'alumni',
  email: 'alice@example.com',
  fullname: 'Alice Alumna',
);

const sessionB = AuthSession(
  accessToken: tokenB,
  firebaseUid: 'uid-B',
  userType: 'other',
  email: 'bob@example.com',
  fullname: 'Bob Guest',
);

const registrationNumberA = 'NITKSAA-A-0101';
const registrationIdA = 101;
const phoneA = '+91 90000 00001';
const ineligibleMessageB = 'This event is open to NITK alumni only.';

/// Stand-in for [AuthController], which cannot run under `flutter test`
/// because it talks to Firebase and Hive directly.
///
/// It publishes changes the way the real controller does: listeners are
/// notified only when [status] changes, and by then the session has already
/// been replaced or cleared.
class FakeAuthController extends ChangeNotifier implements AuthController {
  AuthStatus _status = AuthStatus.checking;
  AuthSession? _session;

  @override
  AuthStatus get status => _status;

  @override
  AuthSession? get session => _session;

  @override
  String? get errorMessage => null;

  @override
  bool get isChecking => _status == AuthStatus.checking;

  @override
  bool get isAuthenticating => _status == AuthStatus.authenticating;

  @override
  bool get isAuthenticated =>
      _status == AuthStatus.authenticated && _session?.isValid == true;

  /// App start, as in `AuthController.initialize()`: a stored session is
  /// restored, otherwise the app starts signed out.
  void restore(AuthSession? stored) {
    _session = stored;
    _setStatus(
      stored == null ? AuthStatus.unauthenticated : AuthStatus.authenticated,
    );
  }

  /// A completed login, as in `AuthController._runLoginFlow()`.
  void logIn(AuthSession session) {
    _setStatus(AuthStatus.authenticating);
    _session = session;
    _setStatus(AuthStatus.authenticated);
  }

  @override
  Future<void> signOut() async {
    _session = null;
    await Future<void>.value();
    _setStatus(AuthStatus.unauthenticated);
  }

  /// A notification that changes nothing about who is signed in.
  void notifyWithoutChange() => notifyListeners();

  @override
  Future<void> initialize() => throw UnimplementedError();

  @override
  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<void> signInWithGoogle() => throw UnimplementedError();

  void _setStatus(AuthStatus status) {
    if (_status == status) return;
    _status = status;
    notifyListeners();
  }
}

/// What the backend holds for one user.
class FakeAccount {
  FakeAccount({this.eligibility, this.registration, this.alumniProfile});

  /// Null makes the eligibility call fail.
  Map<String, dynamic>? eligibility;

  /// Null means the user has no registration (the API answers 404).
  Map<String, dynamic>? registration;

  /// Null means the user is not an alumnus (the API answers 403 alumni_only).
  Map<String, dynamic>? alumniProfile;
}

typedef ApiCall = ({String endpoint, String? token});

/// In-memory backend. Like the real API, every user-scoped answer depends
/// only on the bearer token, so a request shows whose data was asked for.
class FakeEventsRepository extends EventsRepository {
  FakeEventsRepository(this.accounts);

  /// Accounts by access token.
  final Map<String, FakeAccount> accounts;

  final List<ApiCall> calls = [];
  final List<({int registrationId, String token})> paymentOrders = [];

  /// A my-registration response for a token is withheld until its completer
  /// here completes, to keep that request in flight across a user switch.
  final Map<String, Completer<void>> heldMyRegistration = {};

  int _lastRegistrationId = 200;

  Iterable<ApiCall> get userScopedCalls => calls.where((c) => c.token != null);

  int count(String endpoint) =>
      calls.where((c) => c.endpoint == endpoint).length;

  @override
  Future<AppEvent> getPublicEvent(int eventId) async {
    calls.add((endpoint: 'public-event', token: null));
    return AppEvent(
      eventId: eventId,
      slug: 'event-$eventId',
      title: 'Annual Alumni Meet',
      status: 'published',
      startDatetime: DateTime(2099, 1, 10, 18),
      endDatetime: DateTime(2099, 1, 10, 21),
      timezone: 'Asia/Kolkata',
      isVirtual: false,
      isFree: false,
      ticketPrice: 500,
      registrationStatus: 'open',
      registeredCount: 0,
    );
  }

  @override
  Future<Map<String, dynamic>> getRegistrationEligibility(
    int eventId,
    String accessToken,
  ) async {
    calls.add((endpoint: 'eligibility', token: accessToken));
    final eligibility = _account(accessToken).eligibility;
    if (eligibility == null) throw _httpError(500, 'internal_error');
    return eligibility;
  }

  @override
  Future<Map<String, dynamic>?> getMyEventRegistration(
    int eventId,
    String accessToken,
  ) async {
    calls.add((endpoint: 'my-registration', token: accessToken));
    final account = _account(accessToken);
    // Snapshot first: a held response still carries what was true when asked.
    final registration = account.registration;
    await heldMyRegistration[accessToken]?.future;
    return registration;
  }

  @override
  Future<Map<String, dynamic>> getAlumniProfile(String accessToken) async {
    calls.add((endpoint: 'alumni-me', token: accessToken));
    final profile = _account(accessToken).alumniProfile;
    if (profile == null) throw _httpError(403, 'alumni_only');
    return profile;
  }

  @override
  Future<Map<String, dynamic>> registerForEvent(
    int eventId,
    String accessToken,
    String attendeeNote,
  ) async {
    calls.add((endpoint: 'register', token: accessToken));
    final account = _account(accessToken);
    final id = ++_lastRegistrationId;
    return account.registration = {
      'registration_id': id,
      'registration_number': 'NITKSAA-NEW-$id',
      'status': 'payment_pending',
    };
  }

  @override
  Future<Map<String, dynamic>> createPaymentOrder(
    int registrationId,
    String accessToken, {
    required String idempotencyKey,
  }) async {
    calls.add((endpoint: 'payment-order', token: accessToken));
    paymentOrders.add((registrationId: registrationId, token: accessToken));
    final own = _account(accessToken).registration?['registration_id'];
    if (own != registrationId) throw _httpError(404, 'registration_not_found');
    return {'order_id': 'ORD-$registrationId'};
  }

  @override
  Future<Map<String, dynamic>> createPaymentAttempt(
    String orderId,
    String accessToken,
  ) async {
    calls.add((endpoint: 'payment-attempt', token: accessToken));
    // No `checkout` object, so the screen stops before opening Razorpay.
    return <String, dynamic>{};
  }

  FakeAccount _account(String accessToken) {
    final account = accounts[accessToken];
    if (account == null) throw _httpError(401, 'invalid_token');
    return account;
  }

  DioException _httpError(int statusCode, String detail) {
    final request = RequestOptions(path: '/fake');
    return DioException(
      requestOptions: request,
      response: Response<Map<String, dynamic>>(
        requestOptions: request,
        statusCode: statusCode,
        data: {'detail': detail},
      ),
      type: DioExceptionType.badResponse,
    );
  }
}

/// User A is an alumnus registered for [eventX]; user B is neither.
FakeEventsRepository buildBackend({String registrationStatusA = 'registered'}) {
  return FakeEventsRepository({
    tokenA: FakeAccount(
      eligibility: {
        'eligibility_status': 'already_registered',
        'message': 'You are registered for this event.',
      },
      registration: {
        'registration_id': registrationIdA,
        'registration_number': registrationNumberA,
        'status': registrationStatusA,
      },
      alumniProfile: {
        'fullname': sessionA.fullname,
        'email': sessionA.email,
        'phone': phoneA,
      },
    ),
    tokenB: FakeAccount(
      eligibility: {
        'eligibility_status': 'ineligible',
        'message': ineligibleMessageB,
      },
    ),
  });
}
