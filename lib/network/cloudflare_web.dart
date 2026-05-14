// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:venera/foundation/log.dart';
import 'package:venera/network/web_helper_browser.dart';

class CloudflareException implements DioException {
  CloudflareException(this.url, [this.headers = const {}]);

  final String url;
  final Map<String, String> headers;

  @override
  String toString() => "CloudflareException: $url";

  static CloudflareException? fromString(String message) {
    final match = RegExp(r"CloudflareException: (.+)").firstMatch(message);
    if (match == null) return null;
    return CloudflareException(match.group(1)!);
  }

  @override
  RequestOptions get requestOptions => RequestOptions(path: url);
  @override
  Response? get response => null;
  @override
  DioExceptionType get type => DioExceptionType.unknown;
  @override
  Object? get error => null;
  @override
  StackTrace get stackTrace => StackTrace.empty;
  @override
  String? get message => toString();
  @override
  String Function(DioException)? stringBuilder;

  @override
  DioException copyWith({
    RequestOptions? requestOptions,
    Response? response,
    DioExceptionType? type,
    Object? error,
    StackTrace? stackTrace,
    String? message,
    String Function(DioException)? stringBuilder,
  }) => this;
}

void passCloudflare(CloudflareException e, void Function() onFinished) async {
  final client = WebHelperBrowserClient();
  final sessionId = 'cf-${Uri.parse(e.url).host}';
  final state = await client.createSession(
    url: e.url,
    sessionId: sessionId,
    syncCookies: true,
    wait: const Duration(seconds: 60),
  );
  if (state == null) {
    Log.warning(
      'Cloudflare',
      'Helper browser unavailable, opening external browser: ${e.url}',
    );
    await launchUrlString(e.url);
    onFinished();
    return;
  }

  Log.warning(
    'Cloudflare',
    'Opened helper browser for web verification: ${state.viewUrl}',
  );
  if (state.viewUrl.isNotEmpty) {
    await launchUrlString(state.viewUrl);
  }
  if (_containsCloudflareCookie(state)) {
    onFinished();
    return;
  }
  final eventState = await _waitForCloudflareCookieByEvents(
    client,
    sessionId,
    e.url,
    const Duration(seconds: 60),
  );
  if (eventState != null && _containsCloudflareCookie(eventState)) {
    onFinished();
    return;
  }
  for (var i = 0; i < 30; i++) {
    await Future.delayed(const Duration(seconds: 2));
    final refreshed = await client.syncCookies(sessionId, url: e.url);
    if (refreshed != null && _containsCloudflareCookie(refreshed)) {
      onFinished();
      return;
    }
  }
  onFinished();
}

bool _containsCloudflareCookie(WebHelperBrowserState state) {
  return state.cookies.any((cookie) {
    final name = cookie.name.toLowerCase();
    return name == 'cf_clearance' || name == '__cf_bm' || name == '_cfuvid';
  });
}

Future<WebHelperBrowserState?> _waitForCloudflareCookieByEvents(
  WebHelperBrowserClient client,
  String sessionId,
  String url,
  Duration timeout,
) async {
  final endpoint = client.eventsUrl(sessionId, url: url);
  if (endpoint == null || endpoint.isEmpty) return null;
  final uri = Uri.tryParse(endpoint);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return null;
  }
  final wsUrl = uri
      .replace(scheme: uri.scheme == 'https' ? 'wss' : 'ws')
      .toString();
  final completer = Completer<WebHelperBrowserState?>();
  html.WebSocket? socket;
  Timer? timer;

  void complete(WebHelperBrowserState? state) {
    if (completer.isCompleted) return;
    timer?.cancel();
    try {
      socket?.close();
    } catch (_) {}
    completer.complete(state);
  }

  try {
    socket = html.WebSocket(wsUrl);
    timer = Timer(timeout, () => complete(null));
    socket.onMessage.listen((event) {
      try {
        final raw = event.data;
        if (raw is! String) return;
        final decoded = jsonDecode(raw);
        if (decoded is! Map) return;
        final state = WebHelperBrowserState.fromJson(decoded);
        if (_containsCloudflareCookie(state)) {
          complete(state);
        }
      } catch (error, stack) {
        Log.warning(
          'Cloudflare',
          'Failed to parse helper browser event: $error\n$stack',
        );
      }
    });
    socket.onError.listen((_) => complete(null));
    socket.onClose.listen((_) => complete(null));
  } catch (error, stack) {
    timer?.cancel();
    Log.warning(
      'Cloudflare',
      'Helper browser events unavailable: $error\n$stack',
    );
    return null;
  }

  return completer.future;
}

class CloudflareInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final response = err.response;
    if (response != null && _isCloudflareChallenge(response)) {
      handler.next(
        CloudflareException(
          response.requestOptions.uri.toString(),
          Map<String, String>.from(response.requestOptions.headers),
        ),
      );
      return;
    }
    handler.next(err);
  }

  bool _isCloudflareChallenge(Response response) {
    if (response.statusCode != 403) return false;
    final headers = response.headers;
    final mitigated = headers.value('cf-mitigated')?.toLowerCase();
    if (mitigated == 'challenge') return true;
    final server = headers.value('server')?.toLowerCase() ?? '';
    final body = response.data?.toString().toLowerCase() ?? '';
    return server.contains('cloudflare') &&
        (body.contains('cf-challenge') ||
            body.contains('cf-turnstile') ||
            body.contains('challenge-platform'));
  }
}
