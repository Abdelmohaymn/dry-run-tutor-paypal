import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../errors/relay_error.dart';
import '../errors/relay_error_mapper.dart';
import 'dto/chat_dto.dart';
import 'dto/config_dto.dart';
import 'dto/error_dto.dart';
import 'dto/install_dto.dart';
import 'dto/judge_dto.dart';
import 'dto/pro_dto.dart';
import 'dto/problem_dto.dart';
import 'dto/repair_dto.dart';
import 'dto/stt_dto.dart';
import 'sse_parser.dart';

/// Thrown by every [RelayClient] method that fails. Repository
/// implementations catch this and wrap it in a `Result.Err` — this class
/// is `core/network`'s boundary, not the domain's; nothing above the data
/// layer should ever catch a [RelayException] directly.
class RelayException implements Exception {
  const RelayException(this.error);

  final RelayError error;

  @override
  String toString() => 'RelayException($error)';
}

/// The response to `GET /v1/config`: the parsed, restricted projection
/// plus the raw body (for verbatim caching, FR-046) and the `ETag` (so a
/// later revision can conditionally revalidate).
class ConfigResponse {
  const ConfigResponse({required this.parsed, required this.rawJson, this.etag});

  final ConfigDto parsed;
  final String rawJson;
  final String? etag;
}

/// The relay calls, with the header rules from
/// contracts/relay-client.md applied once here rather than left to every
/// caller to remember:
///
/// | Header | Sent on |
/// |---|---|
/// | `X-Install-Id` | every call except `/v1/config` and `/v1/practice`; also sent on `/v1/stt` |
/// | `X-User-Key` | `/v1/chat`, `/v1/judge`, `/v1/repair` only — never `/v1/trial`, never `/v1/stt`, never `/v1/pro/*` |
/// | `X-Provider` | `/v1/chat`, `/v1/judge`, `/v1/repair` only — never `/v1/trial`, never `/v1/pro/*` |
///
/// This class only ever throws [RelayException] (built from
/// `mapErrorEnvelope` — the one code path for a non-2xx body and an SSE
/// `error` frame, research.md R-004) or lets a [MissingMetaFailure]
/// propagate unconverted, because turning that into `UNCLEAR_RETRY` is the
/// session Cubit's decision (research.md R-004 rule 2), not this layer's.
class RelayClient {
  RelayClient(this._dio);

  final Dio _dio;

  /// `POST /v1/install`. Called exactly once, at first launch. Sends no
  /// `X-Install-Id` — this call is what mints it.
  Future<InstallResponseDto> install(String deviceId) async {
    final Map<String, Object?> body = await _postJson(
      '/v1/install',
      InstallRequestDto(platform: 'android', deviceId: deviceId).toJson(),
      headers: const <String, String>{},
    );
    return InstallResponseDto.fromJson(body);
  }

  /// `GET /v1/config`. No `X-Install-Id` — config gates launch before an
  /// install id may even exist yet.
  Future<ConfigResponse> config() async {
    try {
      final Response<String> response = await _dio.get<String>(
        '/v1/config',
        options: Options(responseType: ResponseType.plain),
      );
      final String raw = response.data ?? '{}';
      return ConfigResponse(
        parsed: ConfigDto.fromJson(jsonDecode(raw) as Map<String, dynamic>),
        rawJson: raw,
        etag: response.headers.value('etag'),
      );
    } on DioException catch (e) {
      throw RelayException(_mapTransportOrEnvelope(e, requestProblemId: '', callKind: RelayCallKind.chat));
    }
  }

  /// `GET /v1/daily?date=` — the relay picks the day's problem and records
  /// that this device was active that day. Needs `X-Install-Id`. A
  /// `409 PROBLEM_KILLED` (every candidate withdrawn) surfaces as
  /// [RelayError.problemKilled]; offline as [RelayError.transport].
  Future<DailyResponseDto> daily({
    required String installId,
    required String date,
    String? problemId,
  }) async {
    try {
      final Response<Map<String, dynamic>> response = await _dio.get<Map<String, dynamic>>(
        '/v1/daily',
        queryParameters: <String, String>{
          'date': date,
          if (problemId case final String id) 'problem_id': id,
        },
        options: Options(headers: _headers(installId: installId)),
      );
      return DailyResponseDto.fromJson(response.data!);
    } on DioException catch (e) {
      throw RelayException(_mapTransportOrEnvelope(e, requestProblemId: '', callKind: RelayCallKind.chat));
    }
  }

  /// `GET /v1/practice` — the onboarding warm-up. No `X-Install-Id`: it
  /// is needed before registration can have happened.
  Future<PracticeResponseDto> practice() async {
    try {
      final Response<Map<String, dynamic>> response =
          await _dio.get<Map<String, dynamic>>('/v1/practice');
      return PracticeResponseDto.fromJson(response.data!);
    } on DioException catch (e) {
      throw RelayException(_mapTransportOrEnvelope(e, requestProblemId: '', callKind: RelayCallKind.chat));
    }

  }

  Future<ProblemsResponseDto> problems({required String installId}) async {
    try {
      final Response<Map<String, dynamic>> response = await _dio.get<Map<String, dynamic>>(
        '/v1/problems',
        options: Options(headers: _headers(installId: installId)),
      );
      return ProblemsResponseDto.fromJson(response.data!);
    } on DioException catch (e) {
      throw RelayException(_mapTransportOrEnvelope(e, requestProblemId: '', callKind: RelayCallKind.chat));
    }
  }

  /// `POST /v1/session/reset` — clears today's server-side session state for
  /// one problem so it can be practiced again.
  Future<void> resetSession({
    required String installId,
    required String problemId,
  }) async {
    await _postJson(
      '/v1/session/reset',
      <String, String>{'problem_id': problemId},
      headers: _headers(installId: installId),
      requestProblemId: problemId,
    );
  }

  /// `POST /v1/session/reset` with `reason: recover` — hands back a judge
  /// claim whose verdict never reached this install, leaving the session,
  /// its counters and the trial allowance as they are, so the same session
  /// can be judged again.
  Future<void> recoverJudge({
    required String installId,
    required String problemId,
  }) async {
    await _postJson(
      '/v1/session/reset',
      <String, String>{'problem_id': problemId, 'reason': 'recover'},
      headers: _headers(installId: installId),
      requestProblemId: problemId,
    );
  }

  /// `POST /v1/chat` — the streamed turn. `X-User-Key` and `X-Provider`
  /// are sent when [userKey]/[providerId] are supplied (the keyed path);
  /// omit both for a trial call by calling [trialChat] instead.
  Stream<SseFrame> chat({
    required String installId,
    required ChatRequestDto request,
    String? userKey,
    String? providerId,
  }) {
    return _streamedTurn(
      '/v1/chat',
      request.toJson(),
      installId: installId,
      userKey: userKey,
      providerId: providerId,
    );
  }

  /// `POST /v1/judge` — one assessment, once. Same key/provider rule as
  /// [chat].
  Future<AssessmentDto> judge({
    required String installId,
    required JudgeRequestDto request,
    String? userKey,
    String? providerId,
  }) async {
    final Map<String, Object?> body = await _postJson(
      '/v1/judge',
      request.toJson(),
      headers: _headers(installId: installId, userKey: userKey, providerId: providerId),
      requestProblemId: request.problemId,
      callKind: RelayCallKind.judge,
    );
    return AssessmentDto.fromJson(body);
  }

  /// `POST /v1/repair` — transcript correction on the learner's own key or
  /// the operator's metered trial pool when no key is available.
  Future<RepairResponseDto> repair({
    required String installId,
    required RepairRequestDto request,
    String? userKey,
    String? providerId,
  }) async {
    final Map<String, Object?> body = await _postJson(
      '/v1/repair',
      request.toJson(),
      headers: _headers(installId: installId, userKey: userKey, providerId: providerId),
      requestProblemId: request.problemId,
    );
    return RepairResponseDto.fromJson(body);
  }

  /// `POST /v1/trial`, mode=chat. **Never** sends `X-User-Key` or
  /// `X-Provider` — this path spends the operator's credential
  /// (contracts/relay-client.md).
  Stream<SseFrame> trialChat({required String installId, required ChatRequestDto request}) {
    final Map<String, Object?> body = <String, Object?>{...request.toJson(), 'mode': 'chat'};
    return _streamedTurn('/v1/trial', body, installId: installId);
  }

  /// `POST /v1/trial`, mode=judge.
  Future<AssessmentDto> trialJudge({
    required String installId,
    required JudgeRequestDto request,
  }) async {
    final Map<String, Object?> body = <String, Object?>{...request.toJson(), 'mode': 'judge'};
    final Map<String, Object?> response = await _postJson(
      '/v1/trial',
      body,
      headers: _headers(installId: installId),
      requestProblemId: request.problemId,
      callKind: RelayCallKind.judge,
    );
    return AssessmentDto.fromJson(response);
  }

  /// `POST /v1/stt` — one recorded clip, transcribed server-side on the
  /// operator's Groq key. Sends `X-Install-Id` only: **never** `X-User-Key`
  /// or `X-Provider` (the learner's own key is not used for voice).
  ///
  /// The body is the raw audio bytes, sent as a stream with an explicit
  /// `content-length` so dio does not buffer or re-encode it. The global
  /// `sendTimeout` (10 s) is too short for ~0.5 MB on a slow network, so
  /// this call carries its own 60 s send/receive timeouts.
  ///
  /// Throws [SttRefusedException] for the three voice codes
  /// (`VOICE_EXHAUSTED`, `VOICE_UNAVAILABLE`, `VOICE_BUSY`); every other
  /// failure (offline, timeout, `BAD_REQUEST`, ...) is a [RelayException].
  Future<SttResponseDto> stt({
    required String installId,
    required Uint8List audio,
    required String contentType,
    String? language,
  }) async {
    try {
      final Response<Map<String, dynamic>> response = await _dio.post<Map<String, dynamic>>(
        '/v1/stt',
        data: Stream<List<int>>.fromIterable(<List<int>>[audio]),
        queryParameters: <String, String>{'language': ?language},
        options: Options(
          headers: <String, Object>{
            ..._headers(installId: installId),
            Headers.contentLengthHeader: audio.length,
          },
          contentType: contentType,
          sendTimeout: const Duration(seconds: 60),
          receiveTimeout: const Duration(seconds: 60),
        ),
      );
      return SttResponseDto.fromJson(response.data!);
    } on DioException catch (e) {
      final SttRefusal? refusal = _sttRefusalOf(e);
      if (refusal != null) {
        throw SttRefusedException(refusal);
      }
      throw RelayException(_mapTransportOrEnvelope(e, requestProblemId: '', callKind: RelayCallKind.chat));
    }
  }

  /// `GET /v1/pro/status` — the device's plan, subscription and usage.
  /// `X-Install-Id` only: no user key, no provider.
  Future<ProStatusDto> proStatus({required String installId}) async {
    try {
      final Response<Map<String, dynamic>> response = await _dio.get<Map<String, dynamic>>(
        '/v1/pro/status',
        options: Options(headers: _headers(installId: installId)),
      );
      return ProStatusDto.fromJson(response.data!);
    } on DioException catch (e) {
      throw RelayException(_mapTransportOrEnvelope(e, requestProblemId: '', callKind: RelayCallKind.chat));
    }
  }

  /// `POST /v1/pro/checkout` — starts a PayPal sandbox subscription. The
  /// answer is an `approve_url` to open in the system browser, or
  /// `already_active`. `X-Install-Id` only.
  Future<ProCheckoutDto> proCheckout({required String installId}) async {
    final Map<String, Object?> body = await _postJson(
      '/v1/pro/checkout',
      const <String, Object?>{},
      headers: _headers(installId: installId),
    );
    return ProCheckoutDto.fromJson(body);
  }

  // --- internals ---------------------------------------------------

  Map<String, String> _headers({String? installId, String? userKey, String? providerId}) {
    final Map<String, String> headers = <String, String>{};
    if (installId != null) {
      headers['X-Install-Id'] = installId;
    }
    if (userKey != null) {
      headers['X-User-Key'] = userKey;
    }
    if (providerId != null) {
      headers['X-Provider'] = providerId;
    }
    return headers;
  }

  Future<Map<String, Object?>> _postJson(
    String path,
    Object? data, {
    Map<String, String> headers = const <String, String>{},
    String requestProblemId = '',
    RelayCallKind callKind = RelayCallKind.chat,
  }) async {
    try {
      final Response<Map<String, dynamic>> response = await _dio.post<Map<String, dynamic>>(
        path,
        data: data,
        options: Options(headers: headers),
      );
      return response.data ?? const <String, Object?>{};
    } on DioException catch (e) {
      throw RelayException(
        _mapTransportOrEnvelope(e, requestProblemId: requestProblemId, callKind: callKind),
      );
    }
  }

  Stream<SseFrame> _streamedTurn(
    String path,
    Object? data, {
    required String installId,
    String? userKey,
    String? providerId,
  }) async* {
    final Response<ResponseBody> response = await _dio.post<ResponseBody>(
      path,
      data: data,
      options: Options(
        responseType: ResponseType.stream,
        headers: <String, String>{
          ..._headers(installId: installId, userKey: userKey, providerId: providerId),
          'Accept': 'text/event-stream',
        },
        // Status is never the success signal here (research.md R-004) —
        // both a pre-stream JSON failure and a 200 that opens a stream
        // are read, never thrown by dio itself.
        validateStatus: (int? status) => true,
      ),
    );

    final ResponseBody body = response.data!;
    final String contentType = (body.headers['content-type'] ?? const <String>[]).join(';');
    final String requestProblemId = data is Map<String, Object?>
        ? (data['problem_id'] as String? ?? '')
        : '';

    if (!contentType.contains('text/event-stream')) {
      // A pre-stream failure: the whole body is one JSON error envelope,
      // never SSE-framed (contracts/relay-client.md).
      final List<int> bytes = await body.stream.expand((List<int> chunk) => chunk).toList();
      final Map<String, Object?> json =
          bytes.isEmpty ? const <String, Object?>{} : jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
      throw RelayException(
        mapErrorEnvelope(json, requestProblemId: requestProblemId, callKind: RelayCallKind.chat),
      );
    }

    await for (final SseFrame frame in SseParser.parse(body.stream)) {
      if (frame is ErrorFrame) {
        throw RelayException(
          mapErrorEnvelope(
            frame.rawJson,
            requestProblemId: requestProblemId,
            callKind: RelayCallKind.chat,
          ),
        );
      }
      yield frame;
    }
  }

  /// The voice refusal named by a non-2xx `/v1/stt` envelope, or null when
  /// the body is not one of the three voice codes.
  SttRefusal? _sttRefusalOf(DioException e) {
    Object? data = e.response?.data;
    if (data is String && data.isNotEmpty) {
      try {
        data = jsonDecode(data);
      } on FormatException {
        return null;
      }
    }
    if (data is! Map) {
      return null;
    }
    final Object? error = data['error'];
    final Object? code = error is Map ? error['code'] : null;
    return switch (code) {
      'VOICE_EXHAUSTED' => SttRefusal.exhausted,
      'VOICE_UNAVAILABLE' => SttRefusal.unavailable,
      'VOICE_BUSY' => SttRefusal.busy,
      _ => null,
    };
  }

  RelayError _mapTransportOrEnvelope(
    DioException e, {
    required String requestProblemId,
    required RelayCallKind callKind,
  }) {
    final Object? data = e.response?.data;
    if (data is Map) {
      return mapErrorEnvelope(
        Map<String, Object?>.from(data),
        requestProblemId: requestProblemId,
        callKind: callKind,
      );
    }
    if (data is String && data.isNotEmpty) {
      try {
        final Object? decoded = jsonDecode(data);
        if (decoded is Map) {
          return mapErrorEnvelope(
            Map<String, Object?>.from(decoded),
            requestProblemId: requestProblemId,
            callKind: callKind,
          );
        }
      } on FormatException {
        // Falls through to transport() below.
      }
    }
    // No parseable envelope reached us at all — the request never
    // reached the relay, or the relay's response was not JSON. This is
    // what puts a row in the outbox instead of a message on a screen.
    return const RelayError.transport();
  }
}

/// Re-exported so `dto/error_dto.dart`'s [ErrorDto] stays reachable from
/// call sites that want the typed envelope rather than a raw map (e.g. for
/// logging a redacted summary of a rejected batch).
typedef RelayErrorEnvelope = ErrorDto;
