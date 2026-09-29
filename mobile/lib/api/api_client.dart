import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../auth/auth_session.dart';
import '../core/config.dart';
import '../core/models.dart';
import '../logging/http_log.dart';
import 'access_token_source.dart';
import 'bearer_auth_interceptor.dart';
import 'multipart_body.dart';

/// Authenticated control-plane REST client for the phone.
class ApiClient {
  final AppConfig config;
  final AuthSession session;
  final AccessTokenSource? auth;

  /// An in-process transport for tests; authentication and serialization still run.
  final HttpClientAdapter? httpClientAdapter;
  late final Dio _dio = _buildDio();

  ApiClient({
    required this.config,
    required this.session,
    this.auth,
    this.httpClientAdapter,
  });

  Dio _buildDio() {
    // In-memory subclasses override requests; every real API call requires auth.
    final source =
        auth ?? (throw StateError('API calls require an access token source'));
    final dio = attachHttpLog(
      Dio(
        BaseOptions(
          baseUrl: config.apiBaseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
          // Let the API wrapper turn HTTP failures into short, user-facing
          // ApiExceptions. Transport failures still surface as DioExceptions.
          validateStatus: (status) =>
              status != null && status >= 200 && status < 600,
        ),
      ),
    );
    dio.interceptors.add(
      BearerAuthInterceptor(source, dio, autonomousEnv: config.autonomousEnv),
    );
    final adapter = httpClientAdapter;
    if (adapter != null) dio.httpClientAdapter = adapter;
    return dio;
  }

  // -- auth --
  Future<Map<String, dynamic>?> me() async {
    final res = await _dio.get('/api/auth/me');
    return unwrapApiResponse(res) as Map<String, dynamic>?;
  }

  // -- machines --
  // -- a machine asking to be signed in (`harness login`'s QR, /api/device-auth) --

  /// What the sign-in request [userCode] is: the asking computer's name and fingerprint, where it
  /// asked from, and whether this account already has a machine for that computer.
  Future<MachineSignInRequest> lookupMachineSignIn(String userCode) async {
    final res = await _dio.get(
      '/api/device-auth/lookup',
      queryParameters: {'userCode': userCode},
    );
    return MachineSignInRequest.fromJson(
      unwrapApiResponse(res) as Map<String, dynamic>,
    );
  }

  /// Sign a BROWSER in to this account (its sign-in QR, `k=v`), handing it this phone's trust group
  /// sealed under the QR's pairing code (`viewer/group_sync.dart` `sealHandedRoster`).
  Future<void> approveBrowserSignIn(
    String userCode, {
    required String sealedRoster,
  }) async {
    unwrapApiResponse(
      await _dio.post(
        '/api/device-auth/approve',
        data: {'userCode': userCode, 'sealedRoster': sealedRoster},
      ),
    );
  }

  /// Sign that machine in to this account. Answers the machine id it is now.
  ///
  /// [sealedRoster]: this device's trust group, sealed under the QR's pairing code
  /// (`viewer/group_sync.dart` `sealHandedRoster`), for the machine to open — it joins the group
  /// without either side dialling the other first.
  Future<String> approveMachineSignIn(
    String userCode, {
    String? sealedRoster,
  }) async {
    final res = await _dio.post(
      '/api/device-auth/approve',
      data: {'userCode': userCode, 'sealedRoster': ?sealedRoster},
    );
    final data = unwrapApiResponse(res) as Map<String, dynamic>;
    return data['machineId'] as String;
  }

  /// "Not me": the request is refused, and the machine is told so.
  Future<void> denyMachineSignIn(String userCode) async {
    final res = await _dio.post(
      '/api/device-auth/deny',
      data: {'userCode': userCode},
    );
    unwrapApiResponse(res);
  }

  Future<List<Machine>> machines() async {
    final res = await _dio.get('/api/machines');
    final data = unwrapApiResponse(res) as Map<String, dynamic>;
    final list = data['machines'] as List<dynamic>? ?? [];
    return list
        .map((e) => Machine.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<String?> renameMachine({
    required String machineId,
    required String name,
  }) async {
    final res = await _dio.patch(
      '/api/machines/$machineId',
      data: {'name': name},
      options: Options(headers: {'x-adapter-local': '1'}),
    );
    final data = unwrapApiResponse(res) as Map<String, dynamic>;
    return data['name'] as String?;
  }

  Future<void> deleteMachine({required String machineId}) async {
    final res = await _dio.delete(
      '/api/machines/$machineId',
      options: Options(headers: {'x-adapter-local': '1'}),
    );
    unwrapApiResponse(res);
  }

  // -- the desk: the account's tabs, the same on every computer --

  /// `{revision, tabs}` as the backend holds it (its `routes/desk.ts`); null on
  /// a backend that predates the desk (404) or a session it will not take
  /// (401) — the phone then has no tabs to show and swipes the whole account,
  /// as it did before the desk existed.
  Future<Map<String, dynamic>?> desk() async {
    final res = await _dio.get('/api/desk');
    if (res.statusCode == 404 || res.statusCode == 401) return null;
    return unwrapApiResponse(res) as Map<String, dynamic>?;
  }

  /// Apply [ops] to the desk; answers the desk as it is afterwards. Null under
  /// the same two conditions as [desk].
  Future<Map<String, dynamic>?> deskOps(List<Map<String, dynamic>> ops) async {
    final res = await _dio.post(
      '/api/desk/ops',
      data: {'ops': ops},
      options: Options(headers: {'x-adapter-local': '1'}),
    );
    if (res.statusCode == 404 || res.statusCode == 401) return null;
    return unwrapApiResponse(res) as Map<String, dynamic>?;
  }

  // -- the zoo: the account's daemons and eggs (daemons/README.md), its own document --

  /// `{revision, zoo}` (the backend's `routes/zoo.ts`); null on a backend that
  /// predates the zoo (404) or a session it will not take (401) — the phone
  /// then draws no daemon at all.
  Future<Map<String, dynamic>?> zoo() async {
    final res = await _dio.get('/api/zoo');
    if (res.statusCode == 404 || res.statusCode == 401) return null;
    return unwrapApiResponse(res) as Map<String, dynamic>?;
  }

  /// Apply [ops] in order; answers `{revision, zoo, hatched, grants,
  /// levelUps}`. Null under the same two conditions as [zoo].
  Future<Map<String, dynamic>?> zooOps(List<Map<String, dynamic>> ops) async {
    final res = await _dio.post(
      '/api/zoo/ops',
      data: {'ops': ops},
      options: Options(headers: {'x-adapter-local': '1'}),
    );
    if (res.statusCode == 404 || res.statusCode == 401) return null;
    return unwrapApiResponse(res) as Map<String, dynamic>?;
  }

  // -- voice (backend only: the viewer's own SSO session signs it) --

  /// The words in one WAV recording, in [lang] — `POST /api/voice/stt`, the
  /// endpoint the dial's recordings reach through the CLI, called here with the
  /// token this viewer already holds.
  ///
  /// [lang] must be one the backend serves (`VOICE_WAV_LANGS` in the backend's
  /// `lib/deepgramWav.ts`); anything else is transcribed as English there.
  Future<String> transcribeVoice(Uint8List wav, {required String lang}) async {
    final body = multipartFileBody(
      field: 'file',
      filename: 'voice.wav',
      fileContentType: 'audio/wav',
      file: wav,
      boundary: 'harness-${DateTime.now().microsecondsSinceEpoch}',
    );
    final res = await _dio.post(
      '/api/voice/stt',
      queryParameters: {'lang': lang},
      data: body.bytes,
      options: Options(
        contentType: body.contentType,
        // A take can run five minutes — megabytes on a phone connection — and
        // the backend waits on the transcription provider before it answers.
        sendTimeout: const Duration(minutes: 2),
        receiveTimeout: const Duration(minutes: 2),
      ),
    );
    final data = unwrapApiResponse(res) as Map<String, dynamic>;
    return (data['transcript'] as String? ?? '').trim();
  }
}

class ApiException implements Exception {
  final String message;
  final int? status;
  ApiException(this.message, {this.status});
  @override
  String toString() => message;
}

/// Unwraps the backend's `{success, data, error}` envelope, which both legs
/// speak: the CLI's loopback server mirrors it, and the viewer's own auth calls
/// (`viewer/direct_auth_api.dart`) read it straight from the backend.
dynamic unwrapApiResponse(Response res) {
  final body = res.data;
  if (body is Map && body['success'] == true) {
    return body['data'];
  }
  final error = body is Map ? body['error'] : null;
  final serverMessage = error is Map ? error['message'] : null;
  throw ApiException(
    serverMessage is String && serverMessage.isNotEmpty
        ? serverMessage
        : 'Request failed (${res.statusCode})',
    status: res.statusCode,
  );
}

/// A short explanation of a failed request to the Harness backend.
String describeApiError(Object error) {
  if (error is ApiException) return error.message;
  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionError:
        return 'could not reach Harness. Check your connection and try again.';
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        final limit = error.requestOptions.receiveTimeout?.inSeconds;
        return 'Harness did not answer'
            '${limit == null ? '' : ' within ${limit}s'}. Try again in a moment.';
      case DioExceptionType.badResponse:
        return 'Harness answered '
            '${error.response?.statusCode ?? 'with an error'}.';
      case DioExceptionType.badCertificate:
      case DioExceptionType.cancel:
      case DioExceptionType.transformTimeout:
      case DioExceptionType.unknown:
        return error.message ?? error.error?.toString() ?? 'request failed';
    }
  }
  return '$error';
}

/// `GET /api/device-auth/lookup`: a machine asking this account to sign it in.
class MachineSignInRequest {
  const MachineSignInRequest({
    required this.label,
    this.viewer = false,
    this.pub,
    this.fingerprint,
    this.country,
    this.expiresAt,
    this.existingMachineName,
  });

  final String label;

  /// A browser asking (kind `viewer`), not a machine.
  final bool viewer;

  /// A browser's E2EE public key (base64), to check against its QR and take into the group.
  final String? pub;
  final String? fingerprint;
  final String? country;
  final DateTime? expiresAt;

  /// This account already has a machine for that computer (signing in again reuses it).
  final String? existingMachineName;

  factory MachineSignInRequest.fromJson(Map<String, dynamic> json) {
    final expires = json['expiresAt'];
    final existing = json['existingMachine'];
    return MachineSignInRequest(
      viewer: json['kind'] == 'viewer',
      pub: json['pub'] is String ? json['pub'] as String : null,
      label: (json['label'] as String?)?.trim().isNotEmpty == true
          ? json['label'] as String
          : 'computer',
      fingerprint: json['fingerprint'] as String?,
      country: json['country'] as String?,
      expiresAt: expires is int
          ? DateTime.fromMillisecondsSinceEpoch(expires)
          : null,
      existingMachineName: existing is Map ? existing['name'] as String? : null,
    );
  }
}
