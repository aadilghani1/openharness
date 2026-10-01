import 'package:dio/dio.dart';

import '../api/api_client.dart';
import '../api/access_token_source.dart';
import '../core/config.dart';
import '../logging/http_log.dart';

/// A sign-in or refresh that produced no usable session.
class DirectAuthException implements AccessTokenFailure {
  const DirectAuthException(this.message, {this.signedOut = false});

  final String message;

  /// The session is gone for good: retrying cannot help, only signing in again.
  @override
  final bool signedOut;

  @override
  String toString() => message;
}

/// What `/api/auth/exchange` and `/api/auth/refresh` hand back.
class IssuedTokens {
  const IssuedTokens({
    required this.token,
    this.refreshToken,
    this.expiresIn,
    this.autonomousEnv,
  });

  final String token;
  final String? refreshToken;

  /// Seconds.
  final int? expiresIn;
  final String? autonomousEnv;

  static IssuedTokens? fromData(Object? data) {
    if (data is! Map) return null;
    final token = data['token'], refresh = data['refreshToken'];
    final expiresIn = data['expiresIn'], env = data['autonomousEnv'];
    if (token is! String || token.isEmpty) return null;
    return IssuedTokens(
      token: token,
      refreshToken: refresh is String && refresh.isNotEmpty ? refresh : null,
      expiresIn: expiresIn is int && expiresIn > 0 ? expiresIn : null,
      autonomousEnv: env is String ? env : null,
    );
  }
}

/// The backend's auth endpoints, called by the app itself — in a desktop build the harness CLI
/// calls them (cli.ts `loginCommand`, authSession.ts `refreshRequest`). No bearer rides these:
/// they are how one is got.
class DirectAuthApi {
  DirectAuthApi({required this.config, Dio? dio})
    : _dio =
          dio ??
          attachHttpLog(
            Dio(
              BaseOptions(
                baseUrl: config.apiBaseUrl,
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 30),
                validateStatus: (status) => status != null && status < 600,
              ),
            ),
          );

  final AppConfig config;
  final Dio _dio;

  static const _unavailable =
      'Could not renew your sign-in. That is usually the sign-in service having a moment — '
      'if it keeps happening, sign out and sign in again.';

  Future<({String authorizeUrl, String tx})> authorizeNative(
    String redirectUri,
  ) async {
    final data = unwrapApiResponse(
      await _dio.post(
        '/api/auth/authorize-native',
        data: {
          'redirectUri': redirectUri,
          'autonomousEnv': config.autonomousEnv,
        },
      ),
    );
    final url = data is Map ? data['authorizeUrl'] : null;
    final tx = data is Map ? data['tx'] : null;
    if (url is! String || url.isEmpty || tx is! String || tx.isEmpty) {
      throw const DirectAuthException(
        'The server did not return a sign-in page.',
      );
    }
    return (authorizeUrl: url, tx: tx);
  }

  Future<({String authorizeUrl, String tx})> authorizeWeb(String origin) async {
    final data = unwrapApiResponse(
      await _dio.post(
        '/api/auth/authorize',
        data: {
          'origin': origin,
          'next': '/',
          'autonomousEnv': config.autonomousEnv,
        },
      ),
    );
    final url = data is Map ? data['authorizeUrl'] : null;
    final tx = data is Map ? data['tx'] : null;
    if (url is! String || url.isEmpty || tx is! String || tx.isEmpty) {
      throw const DirectAuthException(
        'The server did not return a sign-in page.',
      );
    }
    return (authorizeUrl: url, tx: tx);
  }

  Future<IssuedTokens> exchange({
    required String code,
    required String state,
    required String tx,
  }) async {
    final data = unwrapApiResponse(
      await _dio.post(
        '/api/auth/exchange',
        data: {'code': code, 'state': state, 'tx': tx},
      ),
    );
    return IssuedTokens.fromData(data) ??
        (throw const DirectAuthException('Sign-in returned no access token.'));
  }

  // -- signing in by a QR a signed-in phone approves (backend routes/qrSignIn.ts) --

  Future<({String code, String pollToken, int expiresIn})> qrStart({required String label}) async {
    final data = unwrapApiResponse(
      await _dio.post('/api/auth/qr/start', data: {'label': label, 'kind': 'viewer'}),
    );
    final code = data is Map ? data['code'] : null, poll = data is Map ? data['pollToken'] : null;
    final expiresIn = data is Map ? data['expiresIn'] : null;
    if (code is! String || poll is! String || expiresIn is! int) {
      throw const DirectAuthException('Sign-in by phone is not available here.');
    }
    return (code: code, pollToken: poll, expiresIn: expiresIn);
  }

  /// `pending`, `denied`, `expired`, or `approved` with the account's email.
  Future<({String status, String? email})> qrPoll(String pollToken) async {
    final data = unwrapApiResponse(await _dio.post('/api/auth/qr/poll', data: {'pollToken': pollToken}));
    final status = data is Map ? data['status'] : null, email = data is Map ? data['email'] : null;
    return (status: status is String ? status : 'expired', email: email is String ? email : null);
  }

  /// The same code, alive a while longer; null when it can live no longer.
  Future<int?> qrExtend(String pollToken) async {
    try {
      final data = unwrapApiResponse(await _dio.post('/api/auth/qr/extend', data: {'pollToken': pollToken}));
      final expiresIn = data is Map ? data['expiresIn'] : null;
      return expiresIn is int ? expiresIn : null;
    } catch (_) {
      return null;
    }
  }

  Future<IssuedTokens> qrClaim(String pollToken) async {
    final data = unwrapApiResponse(await _dio.post('/api/auth/qr/claim', data: {'pollToken': pollToken}));
    return IssuedTokens.fromData(data) ??
        (throw const DirectAuthException('Sign-in returned no access token.'));
  }

  Future<void> qrCancel(String pollToken) async {
    try {
      await _dio.post('/api/auth/qr/cancel', data: {'pollToken': pollToken});
    } catch (_) {}
  }

  /// authSession.ts `refreshRequest`, down to its one subtle rule: only a 401 or
  /// `REFRESH_TOKEN_INVALID` means the session is dead. An unusable refresh token and a real outage
  /// both come back as the same 503, and reading that as dead would delete a refresh token nothing
  /// can bring back — on a blip.
  Future<IssuedTokens> refresh(
    String refreshToken, {
    required String autonomousEnv,
  }) async {
    final Response<dynamic> res;
    try {
      res = await _dio.post(
        '/api/auth/refresh',
        data: {'refreshToken': refreshToken, 'autonomousEnv': autonomousEnv},
      );
    } on DioException {
      throw const DirectAuthException(_unavailable);
    }
    final body = res.data is Map ? res.data as Map : const {};
    final error = body['error'] is Map ? body['error'] as Map : const {};
    if (res.statusCode == 401 || error['code'] == 'REFRESH_TOKEN_INVALID') {
      throw const DirectAuthException(
        'Your sign-in expired. Sign in again.',
        signedOut: true,
      );
    }
    final tokens = body['success'] == false
        ? null
        : IssuedTokens.fromData(body['data']);
    return tokens ?? (throw const DirectAuthException(_unavailable));
  }
}
