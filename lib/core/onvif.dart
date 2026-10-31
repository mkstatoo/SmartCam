import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'sha1.dart';

/// ابزارهای پروتکل ONVIF بدون وابستگی به شبکه (ساخت پیام و پارس پاسخ)؛
/// ارسال واقعی روی شبکه در لایهٔ `services/onvif_client.dart` انجام می‌شود.
class Onvif {
  Onvif._();

  static const String discoveryAddress = '239.255.255.250';
  static const int discoveryPort = 3702;

  static String _uuid(Random r) {
    String h(int n) =>
        List.generate(n, (_) => r.nextInt(16).toRadixString(16)).join();
    return '${h(8)}-${h(4)}-4${h(3)}-a${h(3)}-${h(12)}';
  }

  /// پیام WS-Discovery Probe برای یافتن دوربین‌های ONVIF در شبکهٔ محلی.
  static String buildProbe({Random? random}) {
    final id = _uuid(random ?? Random.secure());
    return '<?xml version="1.0" encoding="UTF-8"?>'
        '<e:Envelope xmlns:e="http://www.w3.org/2003/05/soap-envelope" '
        'xmlns:w="http://schemas.xmlsoap.org/ws/2004/08/addressing" '
        'xmlns:d="http://schemas.xmlsoap.org/ws/2005/04/discovery" '
        'xmlns:dn="http://www.onvif.org/ver10/network/wsdl">'
        '<e:Header><w:MessageID>uuid:$id</w:MessageID>'
        '<w:To e:mustUnderstand="true">urn:schemas-xmlsoap-org:ws:2005:04:discovery</w:To>'
        '<w:Action e:mustUnderstand="true">http://schemas.xmlsoap.org/ws/2005/04/discovery/Probe</w:Action>'
        '</e:Header><e:Body><d:Probe><d:Types>dn:NetworkVideoTransmitter</d:Types></d:Probe></e:Body>'
        '</e:Envelope>';
  }

  /// آدرس‌های سرویس (XAddrs) را از پاسخ ProbeMatches بیرون می‌کشد.
  static List<String> parseProbeMatchXAddrs(String xml) {
    final m = RegExp(
      r'<(?:\w+:)?XAddrs>([^<]*)</(?:\w+:)?XAddrs>',
      caseSensitive: false,
    ).allMatches(xml);
    final urls = <String>[];
    for (final x in m) {
      for (final u in x.group(1)!.trim().split(RegExp(r'\s+'))) {
        if (u.startsWith('http')) urls.add(u);
      }
    }
    // آدرس IPv4 مقدم‌تر از IPv6 / نام‌ها
    urls.sort((a, b) => _isV4(b).compareTo(_isV4(a)));
    return urls;
  }

  static int _isV4(String u) =>
      RegExp(r'^https?://\d{1,3}(\.\d{1,3}){3}[:/]').hasMatch(u) ? 1 : 0;

  /// نام/مدل از Scopes (در صورت وجود).
  static String? parseScopeName(String xml) {
    final s = RegExp(r'onvif://www\.onvif\.org/(?:name|hardware)/([^\s<]+)')
        .firstMatch(xml);
    if (s == null) return null;
    return Uri.decodeComponent(s.group(1)!);
  }

  // ---------------- SOAP ----------------

  static const _nsEnvelope = 'http://www.w3.org/2003/05/soap-envelope';

  /// هدر WS-Security با رمز دیجست (استاندارد ONVIF).
  static String securityHeader(
    String user,
    String pass, {
    DateTime? now,
    List<int>? nonce,
  }) {
    final created = (now ?? DateTime.now().toUtc())
        .toUtc()
        .toIso8601String()
        .replaceFirst(RegExp(r'\.\d+Z$'), 'Z');
    final n = Uint8List.fromList(
      nonce ?? List<int>.generate(16, (_) => Random.secure().nextInt(256)),
    );
    final digest = base64.encode(
      sha1([...n, ...utf8.encode(created), ...utf8.encode(pass)]),
    );
    return '<s:Header><Security s:mustUnderstand="1" '
        'xmlns="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd">'
        '<UsernameToken><Username>${_esc(user)}</Username>'
        '<Password Type="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-username-token-profile-1.0#PasswordDigest">$digest</Password>'
        '<Nonce EncodingType="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-soap-message-security-1.0#Base64Binary">${base64.encode(n)}</Nonce>'
        '<Created xmlns="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd">$created</Created>'
        '</UsernameToken></Security></s:Header>';
  }

  static String envelope(String body, {String header = ''}) =>
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<s:Envelope xmlns:s="$_nsEnvelope">$header<s:Body>$body</s:Body></s:Envelope>';

  static String getCapabilitiesBody() =>
      '<GetCapabilities xmlns="http://www.onvif.org/ver10/device/wsdl">'
      '<Category>Media</Category></GetCapabilities>';

  static String getProfilesBody() =>
      '<GetProfiles xmlns="http://www.onvif.org/ver10/media/wsdl"/>';

  static String getStreamUriBody(String profileToken) =>
      '<GetStreamUri xmlns="http://www.onvif.org/ver10/media/wsdl">'
      '<StreamSetup><Stream xmlns="http://www.onvif.org/ver10/schema">RTP-Unicast</Stream>'
      '<Transport xmlns="http://www.onvif.org/ver10/schema"><Protocol>RTSP</Protocol></Transport></StreamSetup>'
      '<ProfileToken>${_esc(profileToken)}</ProfileToken></GetStreamUri>';

  /// آدرس سرویس Media از پاسخ GetCapabilities.
  static String? parseMediaXAddr(String xml) {
    final media = RegExp(
      r'<(?:\w+:)?Media[ >].*?</(?:\w+:)?Media>',
      dotAll: true,
    ).firstMatch(xml);
    final scope = media?.group(0) ?? xml;
    final m = RegExp(r'<(?:\w+:)?XAddr>([^<]+)</(?:\w+:)?XAddr>')
        .firstMatch(scope);
    return m?.group(1)?.trim();
  }

  /// توکن و نام پروفایل‌ها از پاسخ GetProfiles.
  static List<OnvifProfile> parseProfiles(String xml) {
    final out = <OnvifProfile>[];
    final re = RegExp(
      r'<(?:\w+:)?Profiles\b([^>]*)>(.*?)</(?:\w+:)?Profiles>',
      dotAll: true,
    );
    for (final m in re.allMatches(xml)) {
      final token = RegExp(r'token="([^"]+)"')
          .firstMatch(m.group(1)!)
          ?.group(1);
      if (token == null) continue;
      final name = RegExp(r'<(?:\w+:)?Name>([^<]*)</(?:\w+:)?Name>')
          .firstMatch(m.group(2)!)
          ?.group(1);
      final w = RegExp(r'<(?:\w+:)?Width>(\d+)</(?:\w+:)?Width>')
          .firstMatch(m.group(2)!)
          ?.group(1);
      final h = RegExp(r'<(?:\w+:)?Height>(\d+)</(?:\w+:)?Height>')
          .firstMatch(m.group(2)!)
          ?.group(1);
      out.add(
        OnvifProfile(
          token: token,
          name: name ?? token,
          width: w == null ? null : int.parse(w),
          height: h == null ? null : int.parse(h),
        ),
      );
    }
    return out;
  }

  /// آدرس RTSP از پاسخ GetStreamUri.
  static String? parseStreamUri(String xml) {
    final m = RegExp(r'<(?:\w+:)?Uri>([^<]+)</(?:\w+:)?Uri>').firstMatch(xml);
    return m?.group(1)?.trim().replaceAll('&amp;', '&');
  }

  /// افزودن نام کاربری/رمز به آدرس RTSP (اگر خودش نداشته باشد).
  static String withCredentials(String rtsp, String user, String pass) {
    if (user.isEmpty) return rtsp;
    final u = Uri.parse(rtsp);
    if (u.userInfo.isNotEmpty) return rtsp;
    return u
        .replace(
          userInfo: '${Uri.encodeComponent(user)}:${Uri.encodeComponent(pass)}',
        )
        .toString();
  }

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

class OnvifProfile {
  const OnvifProfile({
    required this.token,
    required this.name,
    this.width,
    this.height,
  });

  final String token;
  final String name;
  final int? width, height;

  int get pixels => (width ?? 0) * (height ?? 0);
}
