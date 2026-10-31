import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// درخواست GET با احراز هویت Basic یا Digest (بدون بسته‌های خارجی).
///
/// ابتدا بدون احراز هویت درخواست می‌دهد؛ اگر ۴۰۱ برگشت، نوع احراز هویت
/// را از هدر WWW-Authenticate می‌خواند و دوباره تلاش می‌کند.
/// [client] باید توسط فراخواننده بسته شود.
Future<HttpClientResponse> authedGet(
  HttpClient client,
  Uri uri, {
  String username = '',
  String password = '',
  Duration timeout = const Duration(seconds: 10),
}) async {
  Future<HttpClientResponse> go([Map<String, String>? headers]) async {
    final req = await client.getUrl(uri).timeout(timeout);
    headers?.forEach(req.headers.set);
    return req.close().timeout(timeout);
  }

  var resp = await go();
  if (resp.statusCode != HttpStatus.unauthorized || username.isEmpty) {
    return resp;
  }

  final www = resp.headers.value(HttpHeaders.wwwAuthenticateHeader) ?? '';
  await resp.drain<void>();

  if (www.toLowerCase().startsWith('basic')) {
    final token = base64.encode(utf8.encode('$username:$password'));
    return go({HttpHeaders.authorizationHeader: 'Basic $token'});
  }
  if (www.toLowerCase().startsWith('digest')) {
    final realm = RegExp(r'realm="([^"]*)"').firstMatch(www)?.group(1) ?? '';
    client.addCredentials(
      uri,
      realm,
      HttpClientDigestCredentials(username, password),
    );
    return go();
  }
  return go();
}

/// ارسال SOAP (POST) برای ONVIF.
Future<String> soapPost(
  Uri uri,
  String xml, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final req = await client.postUrl(uri).timeout(timeout);
    req.headers.set(
      HttpHeaders.contentTypeHeader,
      'application/soap+xml; charset=utf-8',
    );
    req.add(utf8.encode(xml));
    final resp = await req.close().timeout(timeout);
    final body = await resp.transform(utf8.decoder).join().timeout(timeout);
    if (resp.statusCode >= 400 && !body.contains('Envelope')) {
      throw HttpException('HTTP ${resp.statusCode}', uri: uri);
    }
    return body;
  } finally {
    client.close(force: true);
  }
}
