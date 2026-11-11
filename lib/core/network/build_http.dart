// Bundle 213: package:http with the app build header (server version gate).
//
// Files that called the package-level `http.get` / `http.post` import this
// file `as http` instead; everything else of package:http is the same.

import 'dart:convert';

import 'package:http/http.dart' as base;
import 'package:locallink/core/config/app_build.dart';
import 'package:locallink/core/network/session_dead_262.dart';

export 'package:http/http.dart'
    hide get, post, put, delete, patch, head, read, readBytes;

base.Response _note(base.Response r) {
  if (r.statusCode == 426) {
    try {
      AppBuild.onUpgradeRequired?.call(r.body);
    } catch (_) {}
  }
  return r;
}

/// Bundle 262 (D): the own sign-in ended -> one try per 10 min, and every
/// answer to a request with the own token is counted.
Future<base.Response> _send262(Uri url, Map<String, String>? headers,
    Future<base.Response> Function() send) {
  try {
    SessionDead262.instance.check(headers);
  } catch (e) {
    return Future<base.Response>.error(e);
  }
  return send().then((r) {
    try {
      SessionDead262.instance.onHttp(url.path, r.statusCode, headers,
          body: r.statusCode == 401 ? r.body : '');
    } catch (_) {}
    return _note(r);
  });
}

Future<base.Response> get(Uri url, {Map<String, String>? headers}) =>
    _send262(url, headers, () => base.get(url, headers: AppBuild.withHeader(headers)));

Future<base.Response> head(Uri url, {Map<String, String>? headers}) =>
    _send262(url, headers, () => base.head(url, headers: AppBuild.withHeader(headers)));

Future<base.Response> post(Uri url,
        {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
    _send262(
        url,
        headers,
        () => base.post(url,
            headers: AppBuild.withHeader(headers), body: body, encoding: encoding));

Future<base.Response> put(Uri url,
        {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
    _send262(
        url,
        headers,
        () => base.put(url,
            headers: AppBuild.withHeader(headers), body: body, encoding: encoding));

Future<base.Response> patch(Uri url,
        {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
    _send262(
        url,
        headers,
        () => base.patch(url,
            headers: AppBuild.withHeader(headers), body: body, encoding: encoding));

Future<base.Response> delete(Uri url,
        {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
    _send262(
        url,
        headers,
        () => base.delete(url,
            headers: AppBuild.withHeader(headers), body: body, encoding: encoding));

/// A client that adds the build header to every request (uploads,
/// downloads, admin block sync).
class BuildHeaderClient extends base.BaseClient {
  BuildHeaderClient(this._inner);

  final base.Client _inner;

  @override
  Future<base.StreamedResponse> send(base.BaseRequest request) async {
    request.headers[kAppBuildHeader] = '${AppBuild.sent}';
    SessionDead262.instance.check(request.headers); // Bundle 262 (D)
    final r = await _inner.send(request);
    try {
      SessionDead262.instance.onHttp(request.url.path, r.statusCode, request.headers);
    } catch (_) {}
    if (r.statusCode == 426) {
      try {
        AppBuild.onUpgradeRequired?.call('');
      } catch (_) {}
    }
    return r;
  }

  @override
  void close() => _inner.close();
}
