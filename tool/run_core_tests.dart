// اجرای تست‌های هستهٔ تشخیص بدون نیاز به Flutter یا pub.dev:
//   dart run tool/run_core_tests.dart
//
// فریم‌ها در این تست‌ها به‌صورت برنامه‌ای (مصنوعی) ساخته می‌شوند؛ این‌ها فقط
// ورودی تست هستند و هیچ دادهٔ ساختگی‌ای وارد خود اپ نمی‌شود.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../lib/core/detection_engine.dart';
import '../lib/core/fire_smoke_detector.dart';
import '../lib/core/frame.dart';
import '../lib/core/mjpeg_parser.dart';
import '../lib/core/motion_detector.dart';
import '../lib/core/onvif.dart';
import '../lib/core/sha1.dart';
import '../lib/core/zone.dart';

int _passed = 0, _failed = 0;

void check(String name, bool ok, [String detail = '']) {
  if (ok) {
    _passed++;
    print('  ok   $name');
  } else {
    _failed++;
    print('  FAIL $name ${detail.isEmpty ? '' : '-> $detail'}');
  }
}

final _t0 = DateTime.utc(2026, 1, 1, 12);
DateTime _tick(int i) => _t0.add(Duration(milliseconds: 500 * i));

/// پس‌زمینهٔ ثابت با نویز سنسور کوچک.
RgbFrame noisyBg(
  int i, {
  int w = 320,
  int h = 180,
  int level = 90,
  int seed = 1,
  int add = 0,
}) {
  final r = Random(seed * 1000 + i);
  final d = Uint8List(w * h * 3);
  for (var p = 0; p < w * h; p++) {
    // یک گرادیان ملایم تا تصویر کاملاً تخت نباشد
    final base = level + ((p % w) * 30 ~/ w) + add;
    for (var c = 0; c < 3; c++) {
      d[p * 3 + c] = (base + r.nextInt(5) - 2).clamp(0, 255);
    }
  }
  return RgbFrame(w, h, d, time: _tick(i));
}

void paintRect(
  RgbFrame f,
  int x0,
  int y0,
  int x1,
  int y1,
  int r,
  int g,
  int b,
) {
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      final p = (y * f.width + x) * 3;
      f.rgb[p] = r;
      f.rgb[p + 1] = g;
      f.rgb[p + 2] = b;
    }
  }
}

/// ناحیهٔ شعله: هر فریم، پیکسل‌های نارنجی/زرد در الگوی تصادفی متفاوت.
void paintFlame(
  RgbFrame f,
  int x0,
  int y0,
  int x1,
  int y1,
  Random rnd, {
  double fill = 0.6,
}) {
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      if (rnd.nextDouble() < fill) {
        final p = (y * f.width + x) * 3;
        f.rgb[p] = 235 + rnd.nextInt(20);
        f.rgb[p + 1] = 110 + rnd.nextInt(90);
        f.rgb[p + 2] = 20 + rnd.nextInt(40);
      }
    }
  }
}

void main() {
  print('SHA-1');
  check(
    'sha1("abc")',
    hexOf(sha1(utf8.encode('abc'))) ==
        'a9993e364706816aba3e25717850c26c9cd0d89d',
  );
  check(
    'sha1("")',
    hexOf(sha1(<int>[])) == 'da39a3ee5e6b4b0d3255bfef95601890afd80709',
  );
  check(
    'sha1(56-byte vector)',
    hexOf(
          sha1(
            utf8.encode(
              'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq',
            ),
          ),
        ) ==
        '84983e441c3bd26ebaae4aa1f95129e5e54670f1',
  );
  check(
    'sha1(1M x "a")',
    hexOf(sha1(List<int>.filled(1000000, 0x61))) ==
        '34aa973cd4c4daa4f61eeb2bdbad27316534016f',
  );

  print('YUV420 -> RGB');
  {
    // Y=76,U=84,V=255 ~ قرمز؛ Y=255,U=128,V=128 = سفید؛ Y=0 = سیاه
    final w = 4, h = 2;
    final y = Uint8List.fromList([76, 76, 255, 255, 76, 76, 0, 0]);
    final u = Uint8List.fromList([84, 128]);
    final v = Uint8List.fromList([255, 128]);
    final f = RgbFrame.fromYuv420(
      srcWidth: w,
      srcHeight: h,
      y: y,
      u: u,
      v: v,
      yRowStride: 4,
      uvRowStride: 2,
      uvPixelStride: 1,
      targetWidth: 4,
    );
    check(
      'red pixel',
      f.rgb[0] > 240 && f.rgb[1] < 30 && f.rgb[2] < 30,
      '${f.rgb.sublist(0, 3)}',
    );
    check(
      'white pixel',
      f.rgb[6] > 250 && f.rgb[7] > 250 && f.rgb[8] > 250,
      '${f.rgb.sublist(6, 9)}',
    );
    check(
      'black pixel',
      f.rgb[21] < 5 && f.rgb[22] < 5 && f.rgb[23] < 5,
      '${f.rgb.sublist(21, 24)}',
    );
  }

  print('Zone mask');
  {
    final z = DetectionZone(
      include: const [NormRect(0, 0, 0.5, 1)],
      exclude: const [NormRect(0, 0, 0.25, 0.5)],
    );
    final m = z.buildMask(100, 100);
    check('inside include', m[80 * 100 + 40] == 1);
    check('outside include', m[80 * 100 + 70] == 0);
    check('excluded', m[10 * 100 + 10] == 0);
    final z2 = DetectionZone.fromJson(z.toJson());
    check('json round trip', z2.include.length == 1 && z2.exclude.length == 1);
  }

  print('Motion');
  {
    final det = MotionDetector(config: const MotionConfig(sensitivity: 0.6));
    var falsePositives = 0;
    for (var i = 0; i < 40; i++) {
      if (det.process(noisyBg(i)).motion) falsePositives++;
    }
    check(
      'static scene with sensor noise: no motion (40 frames)',
      falsePositives == 0,
      'fp=$falsePositives',
    );

    // جسم متحرک
    MotionResult? last;
    var hits = 0;
    for (var i = 0; i < 12; i++) {
      final f = noisyBg(100 + i);
      paintRect(f, 40 + i * 12, 60, 40 + i * 12 + 40, 120, 220, 220, 220);
      last = det.process(f);
      if (last.motion) hits++;
    }
    check('moving object detected', hits >= 8, 'hits=$hits');
    check(
      'bbox is returned and roughly where the object is',
      last?.bbox != null && last!.bbox!.top < 0.5 && last.bbox!.bottom > 0.4,
      '${last?.bbox}',
    );

    // تغییر سراسری نور → حرکت نیست
    final det2 = MotionDetector();
    for (var i = 0; i < 6; i++) {
      det2.process(noisyBg(i));
    }
    final lit = det2.process(noisyBg(7, add: 70));
    check(
      'global lighting change is not motion',
      !lit.motion && lit.lightingChange,
    );
    var afterLight = 0;
    for (var i = 8; i < 20; i++) {
      if (det2.process(noisyBg(i, add: 70)).motion) afterLight++;
    }
    check('stable after lighting change', afterLight == 0, 'n=$afterLight');

    // ناحیهٔ مستثنی
    final det3 = MotionDetector(
      zone: const DetectionZone(exclude: [NormRect(0.0, 0.0, 1.0, 1.0)]),
    );
    var any = false;
    for (var i = 0; i < 10; i++) {
      final f = noisyBg(i);
      if (i > 3) paintRect(f, 50, 50, 150, 130, 255, 255, 255);
      if (det3.process(f).motion) any = true;
    }
    check('fully excluded zone never triggers', !any);

    // حساسیت: جسم کوچک
    MotionResult run(double s) {
      final d = MotionDetector(config: MotionConfig(sensitivity: s));
      MotionResult? r;
      for (var i = 0; i < 6; i++) {
        d.process(noisyBg(i));
      }
      var any = false;
      for (var i = 6; i < 14; i++) {
        final f = noisyBg(i);
        paintRect(
          f,
          20 + (i % 2) * 20,
          20,
          36 + (i % 2) * 20,
          36,
          240,
          240,
          240,
        );
        r = d.process(f);
        any |= r.motion;
      }
      return MotionResult(motion: any, changedRatio: r!.changedRatio);
    }

    check('high sensitivity sees a small object', run(0.95).motion);
    check('low sensitivity ignores a small object', !run(0.05).motion);
  }

  print('Fire');
  {
    final rnd = Random(7);
    final det = FireSmokeDetector();
    var fpBg = 0;
    for (var i = 0; i < 20; i++) {
      if (det.process(noisyBg(i)).fire) fpBg++;
    }
    check('no fire on plain background', fpBg == 0);

    var fireHits = 0;
    FireSmokeResult? r;
    for (var i = 20; i < 40; i++) {
      final f = noisyBg(i);
      paintFlame(f, 120, 90, 170, 150, rnd);
      r = det.process(f);
      if (r.fire) fireHits++;
    }
    check(
      'flickering flame detected',
      fireHits >= 8,
      'hits=$fireHits score=${r?.fireScore}',
    );
    check(
      'flame bbox near flame location',
      r?.fireBbox != null &&
          r!.fireBbox!.left > 0.25 &&
          r.fireBbox!.right < 0.65,
      '${r?.fireBbox}',
    );

    // جسم نارنجی ثابت (دیوار/جعبه) نباید آتش باشد
    final det2 = FireSmokeDetector();
    var staticFp = 0;
    for (var i = 0; i < 30; i++) {
      final f = noisyBg(i);
      paintRect(f, 100, 60, 200, 140, 240, 140, 40);
      if (det2.process(f).fire) staticFp++;
    }
    check('static orange object is not fire', staticFp == 0, 'fp=$staticFp');

    // ماشین نارنجی در حال عبور از تصویر
    final det3 = FireSmokeDetector();
    var movingFp = 0;
    for (var i = 0; i < 30; i++) {
      final f = noisyBg(i);
      paintRect(f, i * 10, 80, i * 10 + 60, 130, 240, 140, 40);
      if (det3.process(f).fire) movingFp++;
    }
    check('moving orange object is not fire', movingFp == 0, 'fp=$movingFp');

    // نور سفید/زرد ثابت
    final det4 = FireSmokeDetector();
    var lampFp = 0;
    for (var i = 0; i < 20; i++) {
      final f = noisyBg(i);
      paintRect(f, 150, 20, 190, 50, 255, 255, 230);
      if (det4.process(f).fire) lampFp++;
    }
    check('bright white lamp is not fire', lampFp == 0);
  }

  print('Smoke');
  {
    // صحنهٔ رنگی (یک جسم سبز ثابت)، چون در تصویر تک‌رنگ دود غیرفعال است.
    RgbFrame colored(int i) {
      final f = noisyBg(i, level: 60);
      paintRect(f, 0, 0, 60, 180, 40, 120, 50);
      return f;
    }

    final det = FireSmokeDetector();
    for (var i = 0; i < 10; i++) {
      det.process(colored(i));
    }
    var smokeHits = 0;
    FireSmokeResult? r;
    for (var i = 10; i < 30; i++) {
      final f = colored(i);
      // لکهٔ خاکستری روشن‌تر که کم‌کم بزرگ می‌شود
      final grow = 20 + (i - 10) * 3;
      paintRect(
        f,
        160 - grow,
        120 - grow,
        160 + grow,
        120 + grow ~/ 2 + 20,
        140,
        142,
        144,
      );
      r = det.process(f);
      if (r.smoke) smokeHits++;
    }
    check(
      'growing gray plume detected',
      smokeHits >= 3,
      'hits=$smokeHits score=${r?.smokeScore}',
    );

    final det2 = FireSmokeDetector();
    var fp = 0;
    for (var i = 0; i < 40; i++) {
      if (det2.process(noisyBg(i, level: 60)).smoke) fp++;
    }
    check('no smoke on static scene', fp == 0);

    // تصویر تک‌رنگ (IR): همان لکهٔ خاکستری نباید دود حساب شود
    final detIr = FireSmokeDetector();
    var irHits = 0;
    var irMono = false;
    for (var i = 0; i < 30; i++) {
      final f = noisyBg(i, level: 60);
      if (i >= 10) {
        final grow = 20 + (i - 10) * 3;
        paintRect(f, 160 - grow, 120 - grow, 160 + grow, 120 + grow ~/ 2 + 20,
            140, 142, 144);
      }
      final r = detIr.process(f);
      if (r.smoke) irHits++;
      irMono = r.monochrome;
    }
    check('monochrome (IR) scene: smoke disabled', irHits == 0 && irMono,
        'hits=$irHits mono=$irMono');

    // برش ناگهانی صحنه (پرش دوربین) نباید دود بسازد
    final detCut = FireSmokeDetector();
    var cutFp = 0;
    for (var i = 0; i < 40; i++) {
      final f = noisyBg(i, level: i % 6 < 3 ? 60 : 150);
      paintRect(f, 0, 0, 60, 180, 40, 120, 50);
      if (detCut.process(f).smoke) cutFp++;
    }
    check('repeated scene cuts are not smoke', cutFp == 0, 'fp=$cutFp');

    final det3 = FireSmokeDetector();
    for (var i = 0; i < 6; i++) {
      det3.process(noisyBg(i));
    }
    var lightFp = 0;
    for (var i = 6; i < 30; i++) {
      if (det3.process(noisyBg(i, add: 50)).smoke) lightFp++;
    }
    check('global lighting change is not smoke', lightFp == 0, 'fp=$lightFp');
  }

  print('Engine (confirmation + cooldown)');
  {
    final eng = DetectionEngine(
      const EngineConfig(
        fireEnabled: false,
        smokeEnabled: false,
        motionCooldown: Duration(seconds: 10),
      ),
    );
    for (var i = 0; i < 6; i++) {
      eng.process(noisyBg(i));
    }
    final signals = <DetectionSignal>[];
    for (var i = 6; i < 6 + 40; i++) {
      final f = noisyBg(i);
      paintRect(
        f,
        40 + (i % 20) * 8,
        50,
        100 + (i % 20) * 8,
        120,
        230,
        230,
        230,
      );
      signals.addAll(eng.process(f));
    }
    // 40 فریم × 0.5 ثانیه = 20 ثانیه؛ با cooldown 10 ثانیه حداکثر ۲–۳ رویداد
    check(
      'cooldown limits the number of events',
      signals.isNotEmpty && signals.length <= 3,
      'n=${signals.length}',
    );
    check(
      'events are motion typed',
      signals.every((s) => s.type == DetectionType.motion),
    );

    final eng2 = DetectionEngine(
      const EngineConfig(
        motionConfirmFrames: 3,
        fireEnabled: false,
        smokeEnabled: false,
      ),
    );
    for (var i = 0; i < 6; i++) {
      eng2.process(noisyBg(i));
    }
    // فقط یک فریم تکی با جسم → نباید رویداد شود
    final one = noisyBg(6);
    paintRect(one, 50, 50, 150, 130, 255, 255, 255);
    final s1 = eng2.process(one);
    final s2 = eng2.process(noisyBg(7));
    check(
      'single-frame blip does not raise an event',
      s1.isEmpty && s2.isEmpty,
    );
  }

  print('MJPEG parser');
  {
    Uint8List jpeg(int n, int fill) =>
        Uint8List.fromList([0xFF, 0xD8, ...List.filled(n, fill), 0xFF, 0xD9]);
    final a = jpeg(500, 1), b = jpeg(300, 2), c = jpeg(1000, 3);
    String hdr(int n) =>
        '\r\n--frame\r\nContent-Type: image/jpeg\r\nContent-Length: $n\r\n\r\n';
    final stream = BytesBuilder()
      ..add(utf8.encode(hdr(a.length)))
      ..add(a)
      ..add(utf8.encode(hdr(b.length)))
      ..add(b)
      ..add(utf8.encode(hdr(c.length)))
      ..add(c);
    final all = stream.toBytes();

    // یک‌جا
    final p1 = MjpegParser();
    final f1 = p1.add(all);
    check(
      '3 frames from one chunk',
      f1.length == 3 && f1[0].length == a.length && f1[2].length == c.length,
    );

    // بریده‌بریده (۷ بایتی)
    final p2 = MjpegParser();
    final f2 = <Uint8List>[];
    for (var i = 0; i < all.length; i += 7) {
      f2.addAll(p2.add(all.sublist(i, min(i + 7, all.length))));
    }
    check('3 frames from 7-byte chunks', f2.length == 3);
    check(
      'frame content preserved',
      f2[1][5] == 2 &&
          f2[1].length == b.length &&
          f2[1].first == 0xFF &&
          f2[1].last == 0xD9,
    );

    // برش دقیقاً وسط نشانگر FF|D8 و FF|D9
    final p3 = MjpegParser();
    final x = jpeg(50, 9);
    final out3 = <Uint8List>[];
    out3.addAll(p3.add([0x00, 0xFF]));
    out3.addAll(p3.add([0xD8, ...x.sublist(2, x.length - 1)]));
    out3.addAll(p3.add([0xD9, 0x0D, 0x0A]));
    check(
      'marker split across chunks',
      out3.length == 1 && out3[0].length == x.length,
    );

    // زباله و فریم ناقص
    final p4 = MjpegParser(maxFrameBytes: 100);
    final out4 = p4.add([
      ...List.filled(50, 0x41),
      0xFF,
      0xD8,
      ...List.filled(500, 1),
    ]);
    final out5 = p4.add([...jpeg(10, 4)]);
    check(
      'oversized partial frame is dropped, parser recovers',
      out4.isEmpty && out5.length == 1,
    );
  }

  print('ONVIF');
  {
    final probe = Onvif.buildProbe(random: Random(1));
    check(
      'probe has NetworkVideoTransmitter + Probe action',
      probe.contains('NetworkVideoTransmitter') &&
          probe.contains('discovery/Probe'),
    );

    const pm =
        '<?xml version="1.0"?><SOAP-ENV:Envelope><SOAP-ENV:Body><d:ProbeMatches><d:ProbeMatch>'
        '<d:Scopes>onvif://www.onvif.org/name/Front%20Door onvif://www.onvif.org/hardware/ABC</d:Scopes>'
        '<d:XAddrs>http://[fe80::1]/onvif/device_service http://192.168.1.64:80/onvif/device_service</d:XAddrs>'
        '</d:ProbeMatch></d:ProbeMatches></SOAP-ENV:Body></SOAP-ENV:Envelope>';
    final urls = Onvif.parseProbeMatchXAddrs(pm);
    check(
      'XAddrs parsed, IPv4 first',
      urls.length == 2 &&
          urls.first == 'http://192.168.1.64:80/onvif/device_service',
      '$urls',
    );
    check('scope name parsed', Onvif.parseScopeName(pm) == 'Front Door');

    const caps =
        '<tds:GetCapabilitiesResponse><tds:Capabilities>'
        '<tt:Device><tt:XAddr>http://10.0.0.5/onvif/device_service</tt:XAddr></tt:Device>'
        '<tt:Media><tt:XAddr>http://10.0.0.5/onvif/media_service</tt:XAddr></tt:Media>'
        '</tds:Capabilities></tds:GetCapabilitiesResponse>';
    check(
      'media XAddr',
      Onvif.parseMediaXAddr(caps) == 'http://10.0.0.5/onvif/media_service',
    );

    const profs =
        '<trt:GetProfilesResponse>'
        '<trt:Profiles token="Profile_1" fixed="true"><tt:Name>main</tt:Name><tt:VideoEncoderConfiguration><tt:Resolution><tt:Width>1920</tt:Width><tt:Height>1080</tt:Height></tt:Resolution></tt:VideoEncoderConfiguration></trt:Profiles>'
        '<trt:Profiles token="Profile_2"><tt:Name>sub</tt:Name><tt:VideoEncoderConfiguration><tt:Resolution><tt:Width>640</tt:Width><tt:Height>360</tt:Height></tt:Resolution></tt:VideoEncoderConfiguration></trt:Profiles>'
        '</trt:GetProfilesResponse>';
    final ps = Onvif.parseProfiles(profs);
    check(
      '2 profiles with resolution',
      ps.length == 2 &&
          ps[0].token == 'Profile_1' &&
          ps[0].pixels == 1920 * 1080 &&
          ps[1].width == 640,
    );

    const su =
        '<trt:GetStreamUriResponse><trt:MediaUri><tt:Uri>rtsp://10.0.0.5:554/stream?ch=1&amp;sub=1</tt:Uri></trt:MediaUri></trt:GetStreamUriResponse>';
    check(
      'stream uri (entities decoded)',
      Onvif.parseStreamUri(su) == 'rtsp://10.0.0.5:554/stream?ch=1&sub=1',
    );
    check(
      'credentials injected',
      Onvif.withCredentials('rtsp://10.0.0.5:554/s', 'admin', 'p@ss:1') ==
          'rtsp://admin:p%40ss%3A1@10.0.0.5:554/s',
    );
    check(
      'existing credentials are kept',
      Onvif.withCredentials('rtsp://u:p@10.0.0.5/s', 'admin', 'x') ==
          'rtsp://u:p@10.0.0.5/s',
    );

    // دیجست طبق مثال استاندارد WS-UsernameToken: sha1(nonce + created + password)
    final nonce = utf8.encode('abcdefghijklmnop');
    final hdr = Onvif.securityHeader(
      'admin',
      'secret',
      now: DateTime.utc(2026, 1, 2, 3, 4, 5),
      nonce: nonce,
    );
    final expected = base64.encode(
      sha1([
        ...nonce,
        ...utf8.encode('2026-01-02T03:04:05Z'),
        ...utf8.encode('secret'),
      ]),
    );
    check(
      'security header digest + created format',
      hdr.contains(expected) &&
          hdr.contains('2026-01-02T03:04:05Z') &&
          hdr.contains(base64.encode(nonce)),
    );
    check(
      'SOAP body builders are well-formed strings',
      Onvif.envelope(
        Onvif.getStreamUriBody('Profile_1'),
        header: hdr,
      ).contains('<ProfileToken>Profile_1</ProfileToken>'),
    );
  }

  print('\nresult: $_passed passed, $_failed failed');
  if (_failed > 0) throw 'tests failed';
}
