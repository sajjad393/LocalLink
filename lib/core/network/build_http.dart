// Bundle 213: package:http with the app build header (server version gate).
//
// Files that called the package-level `http.get` / `http.post` import this
// file `as http` instead; everything else of package:http is the same.

import 'dart:convert';

import 'package:http/http.dart' as base;
import 'package:locallink/core/config/app_build.dart';

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

Future<base.Response> get(Uri url, {Map<String, String>? headers}) =>
    base.get(url, headers: AppBuild.withHeader(headers)).then(_note);

Future<base.Response> head(Uri url, {Map<String, String>? headers}) =>
    base.head(url, headers: AppBuild.withHeader(headers)).then(_note);

Future<base.Response> post(Uri url,
        {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
    base
        .post(url, headers: AppBuild.withHeader(headers), body: body, encoding: encoding)
        .then(_note);

Future<base.Response> put(Uri url,
        {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
    base
        .put(url, headers: AppBuild.withHeader(headers), body: body, encoding: encoding)
        .then(_note);

Future<base.Response> patch(Uri url,
        {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
    base
        .patch(url, headers: AppBuild.withHeader(headers), body: body, encoding: encoding)
        .then(_note);

Future<base.Response> delete(Uri url,
        {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
    base
        .delete(url, headers: AppBuild.withHeader(headers), body: body, encoding: encoding)
        .then(_note);

/// A client that adds the build header to every request (uploads,
/// downloads, admin block sync).
class BuildHeaderClient extends base.BaseClient {
  BuildHeaderClient(this._inner);

  final base.Client _inner;

  @override
  Future<base.StreamedResponse> send(base.BaseRequest request) async {
    request.headers[kAppBuildHeader] = '${AppBuild.sent}';
    final r = await _inner.send(request);
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
