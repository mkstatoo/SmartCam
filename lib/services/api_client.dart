import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class ApiException implements Exception {
  ApiException(this.status, this.code, this.message, [this.body = const {}]);

  /// ۰ یعنی ارتباط شبکه برقرار نشد.
  final int status;
  final String code;
  final String message;
  final Map<String, dynamic> body;

  bool get isNetwork => status == 0;
  bool get unauthorized => status == 401 && code != 'bad_credentials';

  @override
  String toString() => message;
}

/// کلاینت ساده JSON برای سرور حساب/مجوز (بدون وابستگی اضافه).
class ApiClient {
  ApiClient(this.base);
  final String base;

  Future<Map<String, dynamic>> get(String path, {String? token}) =>
      _send('GET', path, token: token);

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    String? token,
  }) => _send('POST', path, body: body, token: token);

  Future<Map<String, dynamic>> delete(
    String path, {
    Map<String, dynamic>? body,
    String? token,
  }) => _send('DELETE', path, body: body, token: token);

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? token,
  }) async {
    final uri = Uri.parse('$base$path');
    // رمز عبور و توکن نباید روی HTTP ساده بروند (جز در ساخت debug برای توسعه).
    if (uri.scheme != 'https' && !kDebugMode) {
      throw ApiException(0, 'insecure', 'آدرس سرور باید HTTPS باشد');
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final req = await client.openUrl(method, uri);
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (token != null) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      if (body != null) {
        req.headers.set(
          HttpHeaders.contentTypeHeader,
          'application/json; charset=utf-8',
        );
        req.add(utf8.encode(jsonEncode(body)));
      }
      final resp = await req.close().timeout(const Duration(seconds: 25));
      final text = await resp
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 25));
      Map<String, dynamic> json = {};
      try {
        final d = jsonDecode(text);
        if (d is Map) json = d.cast<String, dynamic>();
      } catch (_) {}
      if (resp.statusCode >= 200 && resp.statusCode < 300) return json;
      throw ApiException(
        resp.statusCode,
        json['code'] as String? ?? 'error',
        json['message'] as String? ?? 'خطای سرور (${resp.statusCode})',
        json,
      );
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw ApiException(0, 'network', 'پاسخی از سرور نیامد؛ اینترنت را بررسی کنید');
    } on SocketException {
      throw ApiException(0, 'network', 'ارتباط با سرور برقرار نشد؛ اینترنت را بررسی کنید');
    } on HandshakeException {
      throw ApiException(0, 'tls', 'اتصال امن به سرور برقرار نشد (گواهی HTTPS)');
    } on HttpException catch (e) {
      throw ApiException(0, 'network', 'خطای ارتباط: ${e.message}');
    } finally {
      client.close(force: true);
    }
  }
}
