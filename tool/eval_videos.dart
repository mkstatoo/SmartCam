// ابزار ارزیابی تشخیص روی ویدیوهای واقعی (بدون Flutter).
//
//   dart run tool/eval_videos.dart --init پوشهٔ_ویدیوها          # ساخت manifest خالی
//   dart run tool/eval_videos.dart --manifest manifest.json      # اجرای ارزیابی
//
// نیازمند ffmpeg روی PATH. ویدیوها با همان مسیر برنامه (فریم ۳۲۰ پیکسلی،
// تعداد فریم در ثانیهٔ تحلیل) به DetectionEngine داده می‌شوند و هشدارها با
// برچسب‌های شما (بازه‌های زمانی واقعی) مقایسه می‌شوند.
//
// نکته: فریم‌ها با ffmpeg کوچک می‌شوند، نه با JPEG موبایل؛ تفاوت کوچکی با رفتار
// دقیق روی گوشی ممکن است. اعداد برای «مقایسهٔ نسخه‌ها و تنظیمات» معتبرند.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../lib/core/detection_engine.dart';
import '../lib/core/frame.dart';

const _types = ['motion', 'fire', 'smoke'];
const _videoExt = {'.mp4', '.mkv', '.avi', '.mov', '.webm', '.m4v', '.ts'};

class _Gt {
  _Gt(this.type, this.start, this.end);
  final String type;
  final double start, end;
}

class _Video {
  _Video(this.path, this.gt, this.note);
  final String path;
  final List<_Gt> gt;
  final String note;
}

class _Opts {
  List<double> sens = [0.4, 0.6, 0.8];
  double primary = 0.6;
  double fps = 2;
  int width = 320;
  double tol = 3;
  String? manifest, init, out, dumpFp;
  double? minRecall;
  double? maxFpPerHour;
}

class _Stat {
  int events = 0, detected = 0, fp = 0;
  double negSeconds = 0;
  final List<double> latencies = [];
}

Future<void> main(List<String> args) async {
  final o = _parse(args);
  if (o.init != null) return _initManifest(o.init!);
  if (o.manifest == null) {
    stderr.writeln('استفاده: --manifest FILE  یا  --init DIR  (راهنما: tool/EVAL.md)');
    exit(64);
  }
  if (!await _hasFfmpeg()) {
    stderr.writeln('ffmpeg پیدا نشد. نصبش کنید (مثلاً apt install ffmpeg).');
    exit(69);
  }

  final mf = File(o.manifest!);
  final base = mf.parent.path;
  final j = jsonDecode(await mf.readAsString()) as Map<String, dynamic>;
  o.fps = (j['analysis_fps'] as num?)?.toDouble() ?? o.fps;
  final videos = _loadVideos(j, base);
  if (videos.isEmpty) {
    stderr.writeln('هیچ ویدیویی در manifest نیست.');
    exit(66);
  }

  // stats[sens][type]
  final stats = {
    for (final s in o.sens) s: {for (final t in _types) t: _Stat()},
  };
  final perVideo = <Map<String, dynamic>>[];
  var totalSeconds = 0.0;

  for (final v in videos) {
    stdout.writeln('▶ ${v.path}');
    final size = await _probeSize(v.path, o.width);
    if (size == null) {
      stderr.writeln('  خواندن ویدیو ممکن نشد؛ رد شد.');
      continue;
    }
    final (w, h) = size;
    final engines = {
      for (final s in o.sens)
        s: DetectionEngine(
          EngineConfig(
            motionSensitivity: s,
            fireSensitivity: s,
            smokeSensitivity: s,
          ),
        ),
    };
    // alerts[sens] = [(type, t, tp)]
    final alerts = {for (final s in o.sens) s: <(String, double, bool)>[]};
    final t0 = DateTime.utc(2000);
    var frames = 0;
    final frameBytes = w * h * 3;
    final pending = Uint8List(frameBytes);
    var fill = 0;

    final proc = await Process.start('ffmpeg', [
      '-v', 'error', '-nostdin', '-i', v.path,
      '-vf', 'fps=${o.fps},scale=$w:$h',
      '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-',
    ]);
    final errText = StringBuffer();
    proc.stderr.transform(utf8.decoder).listen(errText.write);

    await for (final chunk in proc.stdout) {
      var off = 0;
      while (off < chunk.length) {
        final n = math.min(frameBytes - fill, chunk.length - off);
        pending.setRange(fill, fill + n, chunk, off);
        fill += n;
        off += n;
        if (fill == frameBytes) {
          fill = 0;
          final t = frames / o.fps;
          frames++;
          final frame = RgbFrame(
            w,
            h,
            Uint8List.fromList(pending),
            time: t0.add(Duration(milliseconds: (t * 1000).round())),
          );
          for (final s in o.sens) {
            for (final sig in engines[s]!.process(frame)) {
              final type = sig.type.name;
              final tp = _matchesGt(v.gt, type, t, o.tol);
              alerts[s]!.add((type, t, tp));
              if (!tp && o.dumpFp != null && s == o.primary) {
                _dump(o.dumpFp!, v.path, type, t, frame);
              }
            }
          }
        }
      }
    }
    final code = await proc.exitCode;
    if (code != 0) stderr.writeln('  ffmpeg کد $code: ${errText.toString().trim()}');
    final dur = frames / o.fps;
    totalSeconds += dur;
    stdout.writeln('  ${frames} فریم تحلیل‌شده (${dur.toStringAsFixed(0)} ثانیه)');

    final vJson = <String, dynamic>{
      'path': v.path,
      'seconds': dur,
      'note': v.note,
      'alerts': <String, dynamic>{},
    };
    for (final s in o.sens) {
      for (final t in _types) {
        final st = stats[s]![t]!;
        final windows = v.gt.where((g) => g.type == t).toList();
        final tAlerts = alerts[s]!.where((a) => a.$1 == t).toList();
        for (final g in windows) {
          st.events++;
          final hit = tAlerts
              .where((a) => a.$2 >= g.start - o.tol && a.$2 <= g.end + o.tol)
              .map((a) => a.$2)
              .toList();
          if (hit.isNotEmpty) {
            st.detected++;
            st.latencies.add(math.max(0.0, hit.reduce(math.min) - g.start));
          }
        }
        st.fp += tAlerts.where((a) => !a.$3).length;
        st.negSeconds += math.max(0.0, dur - _covered(windows, o.tol, dur));
      }
      (vJson['alerts'] as Map)['$s'] = [
        for (final a in alerts[s]!) {'type': a.$1, 't': a.$2, 'tp': a.$3},
      ];
    }
    perVideo.add(vJson);
  }

  stdout.writeln('\nمجموع ویدیو: ${(totalSeconds / 3600).toStringAsFixed(2)} ساعت');
  final report = <String, dynamic>{
    'analysis_fps': o.fps,
    'tolerance_s': o.tol,
    'total_hours': totalSeconds / 3600,
    'videos': perVideo,
    'results': <String, dynamic>{},
  };
  var violations = 0;
  for (final s in o.sens) {
    stdout.writeln('\n── حساسیت $s ${s == o.primary ? '(اصلی)' : ''} ──');
    stdout.writeln(
      'نوع     واقعی  یافته  بازیابی[بازهٔ ۹۵٪]     هشدار-کاذب  ساعت-منفی  کاذب/ساعت      تأخیر-میانه',
    );
    final r = <String, dynamic>{};
    for (final t in _types) {
      final st = stats[s]![t]!;
      final negH = st.negSeconds / 3600;
      final (lo, hi) = _wilson(st.detected, st.events);
      final fpH = negH > 0 ? st.fp / negH : double.nan;
      final fpHi = _fpUpper(st.fp, negH);
      final lat = _median(st.latencies);
      final rec = st.events == 0 ? double.nan : st.detected / st.events;
      stdout.writeln(
        '${t.padRight(7)} ${'${st.events}'.padLeft(5)}  ${'${st.detected}'.padLeft(5)}  '
        '${_pct(rec).padLeft(6)} [${_pct(lo)}–${_pct(hi)}]'.padRight(48) +
            '${'${st.fp}'.padLeft(8)}  ${negH.toStringAsFixed(2).padLeft(9)}  '
                '${_num(fpH).padLeft(8)} (≤${_num(fpHi)})  '
                '${lat == null ? '—' : '${lat.toStringAsFixed(1)}s'}',
      );
      r[t] = {
        'events': st.events,
        'detected': st.detected,
        'recall': rec.isNaN ? null : rec,
        'recall_ci95': lo.isNaN ? null : [lo, hi],
        'false_alerts': st.fp,
        'negative_hours': negH,
        'false_per_hour': fpH.isNaN ? null : fpH,
        'false_per_hour_upper95': fpHi.isNaN ? null : fpHi,
        'median_latency_s': lat,
      };
      if (s == o.primary) {
        if (o.minRecall != null && st.events > 0 && rec < o.minRecall!) {
          stdout.writeln('  ✗ بازیابی $t کمتر از ${o.minRecall}');
          violations++;
        }
        if (o.maxFpPerHour != null && !fpH.isNaN && fpH > o.maxFpPerHour!) {
          stdout.writeln('  ✗ هشدار کاذب $t بیشتر از ${o.maxFpPerHour}/ساعت');
          violations++;
        }
      }
    }
    (report['results'] as Map)['$s'] = r;
  }

  final small = _types.any(
    (t) => stats[o.primary]![t]!.events > 0 && stats[o.primary]![t]!.events < 20,
  );
  if (small) {
    stdout.writeln(
      '\n⚠ تعداد رویداد واقعی کم است (<۲۰ برای دست‌کم یک نوع). بازهٔ اطمینان بزرگ است؛ '
      'بازیابی را قطعی نخوانید.',
    );
  }
  if (totalSeconds < 3600 * 5) {
    stdout.writeln(
      '⚠ ویدیوی منفی کمتر از چند ساعت است؛ «کاذب/ساعت» تخمین ضعیفی است '
      '(عدد داخل پرانتز سقف محتمل ۹۵٪ است).',
    );
  }
  if (o.out != null) {
    await File(o.out!).writeAsString(
      const JsonEncoder.withIndent('  ').convert(report),
    );
    stdout.writeln('\nگزارش JSON: ${o.out}');
  }
  if (violations > 0) exit(1);
}

// ---------------------------------------------------------------- manifest

List<_Video> _loadVideos(Map<String, dynamic> j, String base) {
  final out = <_Video>[];
  for (final e in (j['videos'] as List)) {
    final m = (e as Map).cast<String, dynamic>();
    final p = m['path'] as String;
    final gt = <_Gt>[];
    for (final g in ((m['events'] as List?) ?? const [])) {
      final gm = (g as Map).cast<String, dynamic>();
      final type = gm['type'] as String;
      final a = (gm['start'] as num).toDouble();
      final b = (gm['end'] as num).toDouble();
      if (!_types.contains(type)) {
        throw FormatException('نوع نامعتبر "$type" در $p (مجاز: ${_types.join(', ')})');
      }
      if (b < a) throw FormatException('end < start در $p');
      gt.add(_Gt(type, a, b));
    }
    out.add(
      _Video(
        File(p).isAbsolute ? p : '$base${Platform.pathSeparator}$p',
        gt,
        m['note'] as String? ?? '',
      ),
    );
  }
  return out;
}

Future<void> _initManifest(String dir) async {
  final files = Directory(dir)
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => _videoExt.contains(_ext(f.path)))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  final base = Directory(dir).absolute.path;
  final m = {
    'analysis_fps': 2,
    '_راهنما':
        'برای هر ویدیو، بازه‌های واقعی را در events بنویسید. ویدیوی بدون رویداد = منفی '
        '(مهم‌ترین نوع برای سنجش هشدار کاذب). type: motion | fire | smoke؛ زمان‌ها به ثانیه.',
    'videos': [
      for (final f in files)
        {
          'path': f.absolute.path.substring(base.length + 1),
          'note': '',
          'events': <Map<String, dynamic>>[],
          '_مثال': {'type': 'fire', 'start': 12.0, 'end': 95.5},
        },
    ],
  };
  final out = File('$dir${Platform.pathSeparator}manifest.json');
  await out.writeAsString(const JsonEncoder.withIndent('  ').convert(m));
  stdout.writeln('${files.length} ویدیو پیدا شد → ${out.path}');
  stdout.writeln('events هر ویدیو را پر کنید (خالی = بدون رویداد واقعی) و سپس ارزیابی را اجرا کنید.');
}

// ------------------------------------------------------------------ ffmpeg

Future<bool> _hasFfmpeg() async {
  try {
    final r = await Process.run('ffmpeg', ['-version']);
    return r.exitCode == 0;
  } catch (_) {
    return false;
  }
}

/// اندازهٔ واقعی فریم بعد از چرخش خودکار و کوچک‌سازی را از اولین فریم می‌خواند.
Future<(int, int)?> _probeSize(String path, int width) async {
  final r = await Process.run('ffmpeg', [
    '-v', 'error', '-nostdin', '-i', path,
    '-vf', 'scale=$width:-2', '-frames:v', '1',
    '-f', 'image2pipe', '-c:v', 'ppm', '-',
  ], stdoutEncoding: null);
  if (r.exitCode != 0) return null;
  final b = r.stdout as List<int>;
  // سرایند: P6\nW H\n255\n
  var i = 0;
  final tokens = <String>[];
  while (tokens.length < 4 && i < b.length) {
    while (i < b.length && (b[i] == 10 || b[i] == 32)) {
      i++;
    }
    final s = i;
    while (i < b.length && b[i] != 10 && b[i] != 32) {
      i++;
    }
    tokens.add(String.fromCharCodes(b.sublist(s, i)));
  }
  if (tokens.length < 3 || tokens[0] != 'P6') return null;
  final w = int.tryParse(tokens[1]), h = int.tryParse(tokens[2]);
  if (w == null || h == null) return null;
  return (w, h);
}

// ------------------------------------------------------------------ آمار

bool _matchesGt(List<_Gt> gt, String type, double t, double tol) => gt.any(
  (g) => g.type == type && t >= g.start - tol && t <= g.end + tol,
);

/// طول اجتماع بازه‌های واقعی (با حاشیهٔ tol) که داخل [0, dur] می‌افتد.
double _covered(List<_Gt> w, double tol, double dur) {
  final iv =
      w
          .map((g) => (math.max(0.0, g.start - tol), math.min(dur, g.end + tol)))
          .where((e) => e.$2 > e.$1)
          .toList()
        ..sort((a, b) => a.$1.compareTo(b.$1));
  var total = 0.0;
  double? cs, ce;
  for (final e in iv) {
    if (cs == null) {
      cs = e.$1;
      ce = e.$2;
    } else if (e.$1 <= ce!) {
      ce = math.max(ce, e.$2);
    } else {
      total += ce - cs;
      cs = e.$1;
      ce = e.$2;
    }
  }
  if (cs != null) total += ce! - cs;
  return total;
}

(double, double) _wilson(int k, int n) {
  if (n == 0) return (double.nan, double.nan);
  const z = 1.96;
  final p = k / n;
  final d = 1 + z * z / n;
  final c = (p + z * z / (2 * n)) / d;
  final m = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d;
  return (math.max(0.0, c - m), math.min(1.0, c + m));
}

/// سقف تقریبی ۹۵٪ نرخ هشدار کاذب: برای صفر مورد «قانون سه»، وگرنه تقریب نرمال.
double _fpUpper(int k, double hours) {
  if (hours <= 0) return double.nan;
  if (k == 0) return 3 / hours;
  return (k + 1.96 * math.sqrt(k)) / hours;
}

double? _median(List<double> v) {
  if (v.isEmpty) return null;
  final s = [...v]..sort();
  return s.length.isOdd ? s[s.length ~/ 2] : (s[s.length ~/ 2 - 1] + s[s.length ~/ 2]) / 2;
}

String _pct(double v) => v.isNaN ? '—' : '${(v * 100).toStringAsFixed(0)}%';
String _num(double v) => v.isNaN ? '—' : v.toStringAsFixed(2);
String _ext(String p) {
  final i = p.lastIndexOf('.');
  return i < 0 ? '' : p.substring(i).toLowerCase();
}

// -------------------------------------------------------------- ذخیرهٔ PNG

void _dump(String dir, String video, String type, double t, RgbFrame f) {
  Directory(dir).createSync(recursive: true);
  final name = video.split(Platform.pathSeparator).last.replaceAll(RegExp(r'[^\w\-.]'), '_');
  File('$dir${Platform.pathSeparator}fp_${name}_${type}_${t.toStringAsFixed(1)}s.png')
      .writeAsBytesSync(_png(f));
}

Uint8List _png(RgbFrame f) {
  final raw = BytesBuilder();
  for (var y = 0; y < f.height; y++) {
    raw.addByte(0);
    raw.add(f.rgb.sublist(y * f.width * 3, (y + 1) * f.width * 3));
  }
  final idat = ZLibCodec().encode(raw.toBytes());
  final out = BytesBuilder()..add([137, 80, 78, 71, 13, 10, 26, 10]);
  void chunk(String type, List<int> data) {
    final len = ByteData(4)..setUint32(0, data.length);
    out.add(len.buffer.asUint8List());
    final td = [...type.codeUnits, ...data];
    out.add(td);
    final crc = ByteData(4)..setUint32(0, _crc32(td));
    out.add(crc.buffer.asUint8List());
  }

  final ihdr = ByteData(13)
    ..setUint32(0, f.width)
    ..setUint32(4, f.height)
    ..setUint8(8, 8)
    ..setUint8(9, 2);
  chunk('IHDR', ihdr.buffer.asUint8List());
  chunk('IDAT', idat);
  chunk('IEND', const []);
  return out.toBytes();
}

final List<int> _crcTable = List.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> d) {
  var c = 0xFFFFFFFF;
  for (final b in d) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return c ^ 0xFFFFFFFF;
}

// ------------------------------------------------------------------ آرگومان

_Opts _parse(List<String> a) {
  final o = _Opts();
  for (var i = 0; i < a.length; i++) {
    String next() => a[++i];
    switch (a[i]) {
      case '--manifest':
        o.manifest = next();
      case '--init':
        o.init = next();
      case '--sens':
        o.sens = next().split(',').map(double.parse).toList();
      case '--primary':
        o.primary = double.parse(next());
      case '--fps':
        o.fps = double.parse(next());
      case '--width':
        o.width = int.parse(next());
      case '--tol':
        o.tol = double.parse(next());
      case '--out':
        o.out = next();
      case '--dump-fp':
        o.dumpFp = next();
      case '--min-recall':
        o.minRecall = double.parse(next());
      case '--max-fp-per-hour':
        o.maxFpPerHour = double.parse(next());
      default:
        stderr.writeln('گزینهٔ ناشناخته: ${a[i]}');
        exit(64);
    }
  }
  if (!o.sens.contains(o.primary)) o.sens = [...o.sens, o.primary]..sort();
  return o;
}
