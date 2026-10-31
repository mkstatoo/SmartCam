import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/onvif.dart';
import '../sources/http_auth.dart';

class OnvifDevice {
  const OnvifDevice({required this.xaddr, this.name});
  final String xaddr;
  final String? name;

  String get host => Uri.tryParse(xaddr)?.host ?? xaddr;
}

/// کشف دوربین‌های ONVIF روی شبکهٔ محلی و گرفتن آدرس RTSP آن‌ها.
class OnvifClient {
  /// WS-Discovery: پیام Probe به آدرس multicast ارسال و پاسخ‌ها جمع می‌شود.
  static Future<List<OnvifDevice>> discover({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final found = <String, OnvifDevice>{};
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      final done = Completer<void>();
      socket.listen((ev) {
        if (ev != RawSocketEvent.read) return;
        final d = socket!.receive();
        if (d == null) return;
        final xml = utf8.decode(d.data, allowMalformed: true);
        final urls = Onvif.parseProbeMatchXAddrs(xml);
        if (urls.isEmpty) return;
        final key = Uri.tryParse(urls.first)?.host ?? urls.first;
        found[key] = OnvifDevice(
          xaddr: urls.first,
          name: Onvif.parseScopeName(xml),
        );
      });
      final probe = utf8.encode(Onvif.buildProbe());
      final addr = InternetAddress(Onvif.discoveryAddress);
      // سه بار با فاصله ارسال می‌شود چون UDP تضمینی نیست.
      for (var i = 0; i < 3; i++) {
        socket.send(probe, addr, Onvif.discoveryPort);
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
      Timer(timeout, () {
        if (!done.isCompleted) done.complete();
      });
      await done.future;
    } finally {
      socket?.close();
    }
    return found.values.toList();
  }

  /// آدرس RTSP (با نام کاربری/رمز) را از دوربین می‌پرسد.
  /// پروفایلِ کم‌حجم‌تر (sub-stream) انتخاب می‌شود چون برای تحلیل کافی و سبک‌تر است.
  static Future<String> fetchStreamUri({
    required String deviceServiceUrl,
    String username = '',
    String password = '',
  }) async {
    String header() =>
        username.isEmpty ? '' : Onvif.securityHeader(username, password);

    // ۱) آدرس سرویس Media
    final capsXml = await soapPost(
      Uri.parse(deviceServiceUrl),
      Onvif.envelope(Onvif.getCapabilitiesBody(), header: header()),
    );
    _throwIfFault(capsXml);
    final mediaUrl = Onvif.parseMediaXAddr(capsXml) ?? deviceServiceUrl;

    // ۲) پروفایل‌ها
    final profXml = await soapPost(
      Uri.parse(mediaUrl),
      Onvif.envelope(Onvif.getProfilesBody(), header: header()),
    );
    _throwIfFault(profXml);
    final profiles = Onvif.parseProfiles(profXml);
    if (profiles.isEmpty) {
      throw const FormatException('دوربین هیچ پروفایل ویدیویی‌ای گزارش نکرد');
    }
    profiles.sort((a, b) => a.pixels.compareTo(b.pixels));
    final pick = profiles.firstWhere(
      (p) => (p.width ?? 0) >= 480,
      orElse: () => profiles.last,
    );

    // ۳) آدرس RTSP
    final uriXml = await soapPost(
      Uri.parse(mediaUrl),
      Onvif.envelope(Onvif.getStreamUriBody(pick.token), header: header()),
    );
    _throwIfFault(uriXml);
    final rtsp = Onvif.parseStreamUri(uriXml);
    if (rtsp == null) {
      throw const FormatException('آدرس جریان در پاسخ دوربین نبود');
    }
    // نام کاربری/رمز جدا نگه داشته می‌شود و موقع اتصال به آدرس اضافه می‌شود
    // (CameraConfig.effectiveUrl)، تا رمز در متن آدرس نمایش داده نشود.
    return rtsp;
  }

  static void _throwIfFault(String xml) {
    if (!xml.contains('Fault')) return;
    final reason = RegExp(r'<(?:\w+:)?Text[^>]*>([^<]*)</(?:\w+:)?Text>')
        .firstMatch(xml)
        ?.group(1);
    final auth =
        xml.contains('NotAuthorized') || xml.contains('Sender not Authorized');
    throw HttpException(
      auth
          ? 'نام کاربری یا رمز دوربین نادرست است'
          : 'خطای دوربین: ${reason ?? 'نامشخص'}',
    );
  }
}
