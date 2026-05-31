import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/app_state.dart';
import '../../../core/logger/app_logger.dart';
import '../../../routes/app_routes.dart';
import '../../../theme/theme_provider.dart';

class DeveloperDiagnosticsScreen extends ConsumerWidget {
  const DeveloperDiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final firebaseAppName = AppState.firebaseInitialized
        ? _safeFirebaseAppName()
        : 'N/A';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Developer Diagnostics'),
        leading: BackButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(AppRoutes.home),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          // ── Warning banner ─────────────────────────────────────────────
          Card(
            color: colorScheme.errorContainer,
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: colorScheme.onErrorContainer,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Developer Diagnostics — Not for Production UI',
                      style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onErrorContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ── Foundation Status ───────────────────────────────────────────
          _SectionLabel(title: 'Foundation Status'),
          Card(
            child: Column(
              children: [
                _DiagRow(label: 'App Name', value: 'NITKSAA Event'),
                _divider,
                _DiagRow(label: 'Environment', value: 'Development'),
                _divider,
                _DiagRow(
                  label: 'Firebase',
                  value: AppState.firebaseInitialized
                      ? 'Initialized'
                      : 'Failed',
                  status: AppState.firebaseInitialized
                      ? _Status.ok
                      : _Status.error,
                ),
                _divider,
                _DiagRow(label: 'Firebase App', value: firebaseAppName),
                _divider,
                // Hive is always initialized by the time this screen is reachable;
                // a crash in Hive.initFlutter() would have prevented app startup.
                _DiagRow(
                  label: 'Hive',
                  value: 'Initialized',
                  status: _Status.ok,
                ),
                _divider,
                _DiagRow(
                  label: 'Theme Mode',
                  value: _themeModeLabel(themeMode),
                ),
                _divider,
                _DiagRow(label: 'Platform', value: _platformLabel()),
                _divider,
                _DiagRow(label: 'Router', value: 'Active', status: _Status.ok),
                _divider,
                _DiagRow(label: 'Logger', value: 'Active', status: _Status.ok),
                _divider,
                _DiagRow(
                  label: 'Auth Status',
                  value: FirebaseAuth.instance.currentUser != null
                      ? 'Logged In'
                      : 'Logged Out',
                  status: FirebaseAuth.instance.currentUser != null
                      ? _Status.ok
                      : null,
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Logger Test ─────────────────────────────────────────────────
          _SectionLabel(title: 'Logger Test'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () => AppLogger.debug(
                      'Test debug from developer diagnostics',
                    ),
                    child: const Text('Log Debug'),
                  ),
                  OutlinedButton(
                    onPressed: () =>
                        AppLogger.info('Test info from developer diagnostics'),
                    child: const Text('Log Info'),
                  ),
                  OutlinedButton(
                    onPressed: () => AppLogger.warning(
                      'Test warning from developer diagnostics',
                    ),
                    child: const Text('Log Warning'),
                  ),
                  OutlinedButton(
                    onPressed: () => AppLogger.error(
                      'Test error from developer diagnostics',
                    ),
                    child: const Text('Log Error'),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ── Theme Control ───────────────────────────────────────────────
          _SectionLabel(title: 'Theme Control'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.light,
                    label: Text('Light'),
                    icon: Icon(Icons.light_mode_outlined),
                  ),
                  ButtonSegment(
                    value: ThemeMode.system,
                    label: Text('System'),
                    icon: Icon(Icons.settings_suggest_outlined),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    label: Text('Dark'),
                    icon: Icon(Icons.dark_mode_outlined),
                  ),
                ],
                selected: {themeMode},
                onSelectionChanged: (selection) =>
                    ref.read(themeProvider.notifier).setTheme(selection.first),
              ),
            ),
          ),
          if (kDebugMode) ...[
            const SizedBox(height: 20),
            const _SectionLabel(title: 'Firebase Token Test'),
            const _DevFirebaseTokenCard(),
          ],
        ],
      ),
    );
  }

  static const _divider = Divider(height: 1, indent: 16, endIndent: 16);

  String _safeFirebaseAppName() {
    try {
      return Firebase.app().name;
    } catch (_) {
      return 'Unknown';
    }
  }

  String _themeModeLabel(ThemeMode mode) => switch (mode) {
    ThemeMode.system => 'System',
    ThemeMode.light => 'Light',
    ThemeMode.dark => 'Dark',
  };

  String _platformLabel() {
    if (kIsWeb) return 'Web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'Android',
      TargetPlatform.iOS => 'iOS',
      TargetPlatform.macOS => 'macOS',
      TargetPlatform.windows => 'Windows',
      TargetPlatform.linux => 'Linux',
      TargetPlatform.fuchsia => 'Fuchsia',
    };
  }
}

class _DevFirebaseTokenCard extends StatefulWidget {
  const _DevFirebaseTokenCard();

  @override
  State<_DevFirebaseTokenCard> createState() => _DevFirebaseTokenCardState();
}

class _DevFirebaseTokenCardState extends State<_DevFirebaseTokenCard> {
  static final Future<void> _googleSignInInitialization = GoogleSignIn.instance
      .initialize();
  static const _jsonEncoder = JsonEncoder.withIndent('  ');

  bool _loading = false;
  bool _backendLoading = false;
  bool _meLoading = false;
  bool _tablesLoading = false;
  bool _tableLoading = false;
  bool _fullValidationLoading = false;
  int _validationPassed = 0;
  int _validationFailed = 0;
  String? _firebaseIdToken;
  String? _backendAccessToken;
  String? _tokenPreview;
  String? _status;
  String? _backendStatus;
  String? _meStatus;
  String? _tableStatus;
  DateTime? _lastValidationAt;
  DateTime? _lastTablesRefreshedAt;
  DateTime? _lastTableRefreshedAt;
  Map<String, dynamic>? _backendLoginResponse;
  Map<String, dynamic>? _authMeResponse;
  List<Map<String, dynamic>> _tables = const [];
  Map<String, dynamic>? _selectedTableData;

  String get _backendBaseUrl {
    const configured = String.fromEnvironment('DEV_BACKEND_BASE_URL');
    if (configured.isNotEmpty) return configured;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000';
    }
    return 'http://127.0.0.1:8000';
  }

  Dio get _dio => Dio(
    BaseOptions(
      baseUrl: _backendBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 15),
      headers: const {'Content-Type': 'application/json'},
    ),
  );

  Future<void> _getFirebaseIdToken() async {
    setState(() {
      _loading = true;
      _firebaseIdToken = null;
      _tokenPreview = null;
      _status = 'Starting Google sign-in...';
    });

    try {
      await _ensureGoogleSignInInitialized();

      final googleUser = await GoogleSignIn.instance.authenticate();
      final googleAuth = googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      final userCredential = await FirebaseAuth.instance.signInWithCredential(
        credential,
      );
      final user = userCredential.user;
      final token = await user?.getIdToken(true);

      if (user == null || token == null) {
        throw StateError('FirebaseAuth did not return a user/token.');
      }

      debugPrint('Firebase UID: ${user.uid}');
      debugPrint('Email: ${user.email ?? googleUser.email}');
      debugPrint(
        'Display name: ${user.displayName ?? googleUser.displayName ?? ''}',
      );
      debugPrint('Firebase ID Token length: ${token.length}');
      debugPrint('Firebase ID Token preview: ${_shortToken(token)}');

      if (!mounted) return;
      setState(() {
        _firebaseIdToken = token;
        _tokenPreview = _shortToken(token);
        _status = 'Firebase ID token captured.';
        _lastValidationAt = DateTime.now();
      });
    } catch (error, stackTrace) {
      AppLogger.error(
        'Dev Firebase ID token generation failed',
        error,
        stackTrace,
      );
      if (!mounted) return;
      setState(() {
        _status = 'Failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _validateFirebaseTokenWithBackend() async {
    setState(() {
      _backendLoading = true;
      _backendStatus = 'Validating Firebase token with backend...';
    });

    try {
      final token = await _freshFirebaseIdToken();
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/v1/auth/firebase',
        data: {'token': token},
      );
      final data = response.data ?? <String, dynamic>{};
      final accessToken = data['access_token'] as String?;

      if (accessToken == null || accessToken.isEmpty) {
        throw StateError('Backend did not return an access token.');
      }

      if (!mounted) return;
      setState(() {
        _firebaseIdToken = token;
        _tokenPreview = _shortToken(token);
        _backendAccessToken = accessToken;
        _backendLoginResponse = data;
        _backendStatus = 'Backend login status: ${data['status'] ?? 'ok'}';
        _lastValidationAt = DateTime.now();
      });
    } catch (error, stackTrace) {
      AppLogger.error(
        'Dev backend Firebase validation failed',
        error,
        stackTrace,
      );
      if (!mounted) return;
      setState(() {
        _backendStatus = 'Backend login failed: ${_errorMessage(error)}';
      });
    } finally {
      if (mounted) {
        setState(() => _backendLoading = false);
      }
    }
  }

  Future<void> _validateAuthMe() async {
    setState(() {
      _meLoading = true;
      _meStatus = 'Validating /auth/me...';
    });

    try {
      final accessToken = await _ensureBackendAccessToken();
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/v1/auth/me',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );

      if (!mounted) return;
      setState(() {
        _authMeResponse = response.data ?? <String, dynamic>{};
        _meStatus = '/auth/me returned authenticated user.';
        _lastValidationAt = DateTime.now();
      });
    } catch (error, stackTrace) {
      AppLogger.error('Dev /auth/me validation failed', error, stackTrace);
      if (!mounted) return;
      setState(() {
        _meStatus = '/auth/me failed: ${_errorMessage(error)}';
      });
    } finally {
      if (mounted) {
        setState(() => _meLoading = false);
      }
    }
  }

  Future<void> _runFullValidation() async {
    setState(() {
      _fullValidationLoading = true;
      _validationPassed = 0;
      _validationFailed = 0;
      _status = 'Running Firebase token validation...';
      _backendStatus = 'Pending backend login...';
      _meStatus = 'Pending /auth/me...';
      _tableStatus = 'Pending database validation...';
    });

    var passed = 0;
    var failed = 0;
    String? accessToken;

    try {
      final token = await _freshFirebaseIdToken().timeout(
        const Duration(seconds: 30),
      );
      passed += 1;
      if (!mounted) return;
      setState(() {
        _firebaseIdToken = token;
        _tokenPreview = _shortToken(token);
        _status = 'Firebase token available.';
        _validationPassed = passed;
        _validationFailed = failed;
      });

      try {
        final response = await _dio
            .post<Map<String, dynamic>>(
              '/api/v1/auth/firebase',
              data: {'token': token},
            )
            .timeout(const Duration(seconds: 30));
        final data = response.data ?? <String, dynamic>{};
        accessToken = data['access_token'] as String?;
        if (accessToken == null || accessToken.isEmpty) {
          throw StateError('Backend did not return an access token.');
        }
        passed += 2;
        if (!mounted) return;
        setState(() {
          _backendAccessToken = accessToken;
          _backendLoginResponse = data;
          _backendStatus = 'Backend login passed; JWT generated.';
          _validationPassed = passed;
          _validationFailed = failed;
        });
      } catch (error, stackTrace) {
        failed += 2;
        AppLogger.error(
          'Dev full validation backend login failed',
          error,
          stackTrace,
        );
        if (!mounted) return;
        setState(() {
          _backendStatus = 'Backend login failed: ${_errorMessage(error)}';
          _validationPassed = passed;
          _validationFailed = failed;
        });
      }
    } catch (error, stackTrace) {
      failed += 6;
      AppLogger.error(
        'Dev full validation Firebase token failed',
        error,
        stackTrace,
      );
      if (!mounted) return;
      setState(() {
        _status = 'Firebase token failed: ${_errorMessage(error)}';
        _backendStatus = 'Skipped backend login.';
        _meStatus = 'Skipped /auth/me.';
        _tableStatus = 'Skipped database validation.';
        _validationPassed = passed;
        _validationFailed = failed;
        _lastValidationAt = DateTime.now();
        _fullValidationLoading = false;
      });
      return;
    }

    if (accessToken != null && accessToken.isNotEmpty) {
      try {
        final response = await _dio
            .get<Map<String, dynamic>>(
              '/api/v1/auth/me',
              options: Options(
                headers: {'Authorization': 'Bearer $accessToken'},
              ),
            )
            .timeout(const Duration(seconds: 30));
        passed += 1;
        if (!mounted) return;
        setState(() {
          _authMeResponse = response.data ?? <String, dynamic>{};
          _meStatus = '/auth/me passed.';
          _validationPassed = passed;
          _validationFailed = failed;
        });
      } catch (error, stackTrace) {
        failed += 1;
        AppLogger.error(
          'Dev full validation /auth/me failed',
          error,
          stackTrace,
        );
        if (!mounted) return;
        setState(() {
          _meStatus = '/auth/me failed: ${_errorMessage(error)}';
          _validationPassed = passed;
          _validationFailed = failed;
        });
      }

      try {
        final response = await _dio
            .get<Map<String, dynamic>>(
              '/api/v1/dev/diagnostics/db/tables',
              options: Options(
                headers: {'Authorization': 'Bearer $accessToken'},
              ),
            )
            .timeout(const Duration(seconds: 30));
        final rawTables = response.data?['tables'];
        final tables = rawTables is List
            ? rawTables
                  .whereType<Map>()
                  .map((table) => Map<String, dynamic>.from(table))
                  .toList()
            : <Map<String, dynamic>>[];
        passed += 1;
        if (!mounted) return;
        setState(() {
          _tables = tables;
          _tableStatus = 'Database tables loaded.';
          _lastTablesRefreshedAt = DateTime.now();
          _validationPassed = passed;
          _validationFailed = failed;
        });
      } catch (error, stackTrace) {
        failed += 1;
        AppLogger.error(
          'Dev full validation table list failed',
          error,
          stackTrace,
        );
        if (!mounted) return;
        setState(() {
          _tableStatus = 'Database tables failed: ${_errorMessage(error)}';
          _validationPassed = passed;
          _validationFailed = failed;
        });
      }

      try {
        final response = await _dio
            .get<Map<String, dynamic>>(
              '/api/v1/dev/diagnostics/db/event_users',
              options: Options(
                headers: {'Authorization': 'Bearer $accessToken'},
              ),
            )
            .timeout(const Duration(seconds: 30));
        passed += 1;
        if (!mounted) return;
        setState(() {
          _selectedTableData = response.data ?? <String, dynamic>{};
          _tableStatus = 'event_users loaded.';
          _lastTableRefreshedAt = DateTime.now();
          _validationPassed = passed;
          _validationFailed = failed;
        });
      } catch (error, stackTrace) {
        failed += 1;
        AppLogger.error(
          'Dev full validation event_users failed',
          error,
          stackTrace,
        );
        if (!mounted) return;
        setState(() {
          _tableStatus = 'event_users failed: ${_errorMessage(error)}';
          _validationPassed = passed;
          _validationFailed = failed;
        });
      }
    }

    if (!mounted) return;
    setState(() {
      _lastValidationAt = DateTime.now();
      _fullValidationLoading = false;
    });
  }

  Future<void> _refreshTables() async {
    setState(() {
      _tablesLoading = true;
      _tableStatus = 'Refreshing database table list...';
    });

    try {
      final accessToken = await _ensureBackendAccessToken();
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/v1/dev/diagnostics/db/tables',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      final rawTables = response.data?['tables'];
      final tables = rawTables is List
          ? rawTables
                .whereType<Map>()
                .map((table) => Map<String, dynamic>.from(table))
                .toList()
          : <Map<String, dynamic>>[];

      if (!mounted) return;
      setState(() {
        _tables = tables;
        _tableStatus = 'Database table list refreshed.';
        _lastTablesRefreshedAt = DateTime.now();
      });
    } catch (error, stackTrace) {
      AppLogger.error('Dev database table refresh failed', error, stackTrace);
      if (!mounted) return;
      setState(() {
        _tableStatus = 'Table refresh failed: ${_errorMessage(error)}';
      });
    } finally {
      if (mounted) {
        setState(() => _tablesLoading = false);
      }
    }
  }

  Future<void> _refreshEventUsers() => _refreshTable('event_users');

  Future<void> _refreshTable(String tableName) async {
    setState(() {
      _tableLoading = true;
      _tableStatus = 'Refreshing $tableName...';
    });

    try {
      final accessToken = await _ensureBackendAccessToken();
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/v1/dev/diagnostics/db/$tableName',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );

      if (!mounted) return;
      setState(() {
        _selectedTableData = response.data ?? <String, dynamic>{};
        _tableStatus = '$tableName refreshed.';
        _lastTableRefreshedAt = DateTime.now();
      });
    } catch (error, stackTrace) {
      AppLogger.error('Dev database table fetch failed', error, stackTrace);
      if (!mounted) return;
      setState(() {
        _selectedTableData = {
          'table': tableName,
          'available': false,
          'row_count': 0,
          'rows': const [],
          'error': _errorMessage(error),
        };
        _tableStatus = '$tableName failed: ${_errorMessage(error)}';
      });
    } finally {
      if (mounted) {
        setState(() => _tableLoading = false);
      }
    }
  }

  Future<void> _ensureGoogleSignInInitialized() async {
    await _googleSignInInitialization;
  }

  Future<String> _freshFirebaseIdToken() async {
    var user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      await _getFirebaseIdToken();
      user = FirebaseAuth.instance.currentUser;
    }

    final token = await user?.getIdToken(true);
    if (user == null || token == null || token.isEmpty) {
      throw StateError('Firebase user or ID token is unavailable.');
    }
    return token;
  }

  Future<String> _ensureBackendAccessToken() async {
    final existing = _backendAccessToken;
    if (existing != null && existing.isNotEmpty) return existing;

    final token = await _freshFirebaseIdToken();
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/auth/firebase',
      data: {'token': token},
    );
    final accessToken = response.data?['access_token'] as String?;
    if (accessToken == null || accessToken.isEmpty) {
      throw StateError('Backend access token is unavailable.');
    }

    if (mounted) {
      setState(() {
        _firebaseIdToken = token;
        _tokenPreview = _shortToken(token);
        _backendAccessToken = accessToken;
        _backendLoginResponse = response.data ?? <String, dynamic>{};
        _backendStatus =
            'Backend login status: ${response.data?['status'] ?? 'ok'}';
      });
    }
    return accessToken;
  }

  Future<void> _copyFirebaseIdToken() async {
    final token = _firebaseIdToken;
    if (token == null) return;

    await Clipboard.setData(ClipboardData(text: token));
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Firebase ID token copied.')));
  }

  String _shortToken(String token) {
    if (token.length <= 40) return token;
    return '${token.substring(0, 20)}...${token.substring(token.length - 20)}';
  }

  String _errorMessage(Object error) {
    if (error is DioException) {
      final status = error.response?.statusCode;
      final data = error.response?.data;
      return status == null
          ? error.message ?? error.type.name
          : '$status $data';
    }
    return error.toString();
  }

  String _formatTimestamp(DateTime? timestamp) {
    if (timestamp == null) return 'Never';
    final local = timestamp.toLocal();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final day = local.day.toString().padLeft(2, '0');
    final month = months[local.month - 1];
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day-$month-${local.year} $hour:$minute';
  }

  _IndicatorState _stateFor(bool passed, bool failed) {
    if (passed) return _IndicatorState.passed;
    if (failed) return _IndicatorState.failed;
    return _IndicatorState.pending;
  }

  Widget _statusPill(String label, _IndicatorState state) {
    final colorScheme = Theme.of(context).colorScheme;
    final (text, color, foreground) = switch (state) {
      _IndicatorState.passed => (
        '🟢 $label',
        Colors.green.withValues(alpha: 0.12),
        Colors.green.shade800,
      ),
      _IndicatorState.failed => (
        '🔴 $label',
        colorScheme.errorContainer,
        colorScheme.onErrorContainer,
      ),
      _IndicatorState.pending => (
        '🟡 $label',
        colorScheme.surfaceContainerHighest,
        colorScheme.onSurfaceVariant,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _authSummary(User? user) {
    final backendFailed =
        _backendStatus?.toLowerCase().contains('failed') ?? false;
    final meFailed = _meStatus?.toLowerCase().contains('failed') ?? false;
    final userName =
        _authMeResponse?['fullname']?.toString() ??
        _backendLoginResponse?['fullname']?.toString() ??
        user?.displayName ??
        'N/A';
    final email =
        _authMeResponse?['email']?.toString() ??
        _backendLoginResponse?['email']?.toString() ??
        user?.email ??
        'N/A';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _statusPill(
                'Firebase Login',
                _stateFor(user != null, _status?.startsWith('Failed') ?? false),
              ),
              _statusPill(
                'Backend Login',
                _stateFor(_backendLoginResponse != null, backendFailed),
              ),
              _statusPill(
                'JWT Generated',
                _stateFor(_backendAccessToken != null, backendFailed),
              ),
              _statusPill(
                '/auth/me',
                _stateFor(_authMeResponse != null, meFailed),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _SummaryField(label: 'User', value: userName),
          const SizedBox(height: 8),
          _SummaryField(label: 'Email', value: email),
          const SizedBox(height: 8),
          _SummaryField(
            label: 'Firebase UID',
            value:
                user?.uid ??
                _authMeResponse?['firebase_uid']?.toString() ??
                'N/A',
          ),
          const SizedBox(height: 8),
          _SummaryField(
            label: 'Last Validation',
            value: _formatTimestamp(_lastValidationAt),
          ),
          if (_validationPassed > 0 || _validationFailed > 0) ...[
            const SizedBox(height: 8),
            _SummaryField(
              label: 'Full Validation',
              value: 'Passed: $_validationPassed  Failed: $_validationFailed',
            ),
          ],
        ],
      ),
    );
  }

  Widget _jsonBlock(String title, Object? value) {
    if (value == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text(title, style: Theme.of(context).textTheme.labelLarge),
        subtitle: const Text('Show Raw Response'),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                _jsonEncoder.convert(value),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tableCards() {
    if (_tablesLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: 12),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_tables.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 12),
        child: Text('No table metadata loaded.'),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        children: [
          for (final table in _tables)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: InkWell(
                onTap: _tableLoading
                    ? null
                    : () => _refreshTable(table['name'].toString()),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        table['name']?.toString() ?? 'unknown',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (table['available'] == true)
                      _CountBadge(value: table['row_count']?.toString() ?? '0')
                    else
                      Text(
                        table['error']?.toString() ?? 'Unavailable',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    const SizedBox(width: 6),
                    const Icon(Icons.chevron_right, size: 18),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _selectedTableView() {
    final data = _selectedTableData;
    if (_tableLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: 12),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (data == null) return const SizedBox.shrink();

    final tableName = data['table']?.toString() ?? 'table';
    final rows = data['rows'] is List ? data['rows'] as List : const [];
    final error = data['error'];

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$tableName (${data['row_count'] ?? rows.length} rows)',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Text('Last refreshed: ${_formatTimestamp(_lastTableRefreshedAt)}'),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(
              'Error: $error',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ] else if (rows.isEmpty) ...[
            const SizedBox(height: 8),
            const Text('No rows found.'),
          ] else ...[
            const SizedBox(height: 8),
            for (var index = 0; index < rows.length; index++)
              _rowCard(
                tableName,
                index + 1,
                Map<String, dynamic>.from(rows[index] as Map),
              ),
          ],
        ],
      ),
    );
  }

  Widget _rowCard(String tableName, int index, Map<String, dynamic> row) {
    final title = _rowTitle(tableName, row, index);
    final fields = _displayFieldsForRow(tableName, row);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            for (final entry in fields.entries) _KeyValueLine(entry: entry),
          ],
        ),
      ),
    );
  }

  String _rowTitle(String tableName, Map<String, dynamic> row, int index) {
    if (tableName == 'event_users') {
      return row['fullname']?.toString() ??
          row['email']?.toString() ??
          'User $index';
    }
    return row['title']?.toString() ??
        row['event_type']?.toString() ??
        row['notification_id']?.toString() ??
        'Row $index';
  }

  Map<String, dynamic> _displayFieldsForRow(
    String tableName,
    Map<String, dynamic> row,
  ) {
    if (tableName == 'event_users') {
      return {
        'Email': row['email'],
        'User Type': row['user_type'],
        'Ref ID': row['ref_id'],
        'Graduation Year': row['graduation_year'],
        'Last Login': row['last_login'],
        'Suspended': row['is_suspended'],
      };
    }

    final preferred = <String>[
      'event_id',
      'title',
      'email',
      'status',
      'event_type',
      'entity_type',
      'created_at',
      'updated_at',
      'registered_at',
      'checked_in_at',
      'scanned_at',
    ];
    final fields = <String, dynamic>{};
    for (final key in preferred) {
      if (row.containsKey(key)) fields[_titleCase(key)] = row[key];
    }
    if (fields.isNotEmpty) return fields;
    return row.map((key, value) => MapEntry(_titleCase(key), value));
  }

  String _titleCase(String value) {
    return value
        .split('_')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final firebaseUser = FirebaseAuth.instance.currentUser;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Auth Validation', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Backend: $_backendBaseUrl',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            _authSummary(firebaseUser),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _fullValidationLoading ? null : _runFullValidation,
              icon: _fullValidationLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_circle_outline),
              label: const Text('Run Full Validation'),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _loading ? null : _getFirebaseIdToken,
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.key_outlined),
              label: const Text('Dev: Get Firebase ID Token'),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _backendLoading
                      ? null
                      : _validateFirebaseTokenWithBackend,
                  icon: _backendLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.verified_user_outlined),
                  label: const Text('Validate Firebase Token with Backend'),
                ),
                OutlinedButton.icon(
                  onPressed: _meLoading ? null : _validateAuthMe,
                  icon: const Icon(Icons.person_search_outlined),
                  label: const Text('Validate /auth/me'),
                ),
                OutlinedButton.icon(
                  onPressed: _tableLoading ? null : _refreshEventUsers,
                  icon: const Icon(Icons.manage_accounts_outlined),
                  label: const Text('Refresh event_users'),
                ),
                OutlinedButton.icon(
                  onPressed: _tablesLoading ? null : _refreshTables,
                  icon: const Icon(Icons.table_chart_outlined),
                  label: const Text('Refresh Database Tables'),
                ),
              ],
            ),
            if (_firebaseIdToken != null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _copyFirebaseIdToken,
                icon: const Icon(Icons.copy_outlined),
                label: const Text('Copy Firebase ID Token'),
              ),
            ],
            if (_status != null ||
                _backendStatus != null ||
                _meStatus != null ||
                _tableStatus != null) ...[
              const SizedBox(height: 12),
              if (_status != null)
                Text(
                  _status!,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              if (_backendStatus != null)
                Text(
                  _backendStatus!,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              if (_meStatus != null)
                Text(
                  _meStatus!,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              if (_tableStatus != null)
                Text(
                  _tableStatus!,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
            if (_tokenPreview != null) ...[
              const SizedBox(height: 8),
              Text(
                'Token length: ${_firebaseIdToken?.length ?? 0}',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              SelectableText(
                _tokenPreview!,
                style: textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
              ),
            ],
            _jsonBlock('Backend login response', _backendLoginResponse),
            _jsonBlock('/auth/me response', _authMeResponse),
            const SizedBox(height: 20),
            Text('Database Viewer', style: textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Tables refreshed: ${_formatTimestamp(_lastTablesRefreshedAt)}',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            _tableCards(),
            _selectedTableView(),
          ],
        ),
      ),
    );
  }
}

// ── Status enum ──────────────────────────────────────────────────────────────

enum _Status { ok, error }

enum _IndicatorState { passed, pending, failed }

class _SummaryField extends StatelessWidget {
  const _SummaryField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        SelectableText(
          value,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 34),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        value,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _KeyValueLine extends StatelessWidget {
  const _KeyValueLine({required this.entry});

  final MapEntry<String, dynamic> entry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 360;
          final label = Text(
            entry.key,
            style: const TextStyle(fontWeight: FontWeight.w600),
          );
          final value = SelectableText(entry.value?.toString() ?? 'NULL');
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [label, const SizedBox(height: 2), value],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 132, child: label),
              Expanded(child: value),
            ],
          );
        },
      ),
    );
  }
}

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

// ── Diagnostic row ───────────────────────────────────────────────────────────

class _DiagRow extends StatelessWidget {
  const _DiagRow({required this.label, required this.value, this.status});

  final String label;
  final String value;
  final _Status? status;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    Widget? statusIcon;
    if (status != null) {
      statusIcon = Icon(
        status == _Status.ok ? Icons.check_circle_outline : Icons.error_outline,
        color: status == _Status.ok ? Colors.green : colorScheme.error,
        size: 16,
      );
    }

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
          ),
          if (statusIcon != null) ...[const SizedBox(width: 6), statusIcon],
        ],
      ),
    );
  }
}
