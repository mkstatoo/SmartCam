import 'dart:typed_data';

import 'frame.dart';
import 'zone.dart';

class FireSmokeConfig {
  const FireSmokeConfig({
    this.fireSensitivity = 0.6,
    this.smokeSensitivity = 0.5,
    this.analysisWidth = 160,
  });

  final double fireSensitivity;
  final double smokeSensitivity;
  final int analysisWidth;

  /// کمترین قرمزی لازم برای پیکسل «شبیه شعله».
  int get redThreshold => _lerp(215, 150, fireSensitivity).round();

  /// حداقل نسبت پیکسل‌های «شعله‌ور و سوسوزن» به کل ناحیهٔ پایش.
  double get minFireRatio => _lerp(0.02, 0.003, fireSensitivity);

  /// حداقل نسبت پیکسل‌های «دودی» به کل ناحیهٔ پایش.
  double get minSmokeRatio => _lerp(0.10, 0.025, smokeSensitivity);

  static double _lerp(double a, double b, double t) =>
      a + (b - a) * t.clamp(0.0, 1.0);
}

class FireSmokeResult {
  const FireSmokeResult({
    this.fire = false,
    this.fireScore = 0,
    this.fireBbox,
    this.smoke = false,
    this.smokeScore = 0,
    this.smokeBbox,
  });

  final bool fire;

  /// نسبت پیکسل‌های شعله‌ور سوسوزن به کل ناحیهٔ پایش.
  final double fireScore;
  final NormRect? fireBbox;
  final bool smoke;
  final double smokeScore;
  final NormRect? smokeBbox;
}

/// تشخیص آتش و دود بدون مدل یادگیری ماشین (قاعده‌محور):
///
/// آتش: پیکسل‌هایی با رنگ شعله (R بالا، R ≥ G > B، اختلاف R−B زیاد) که در
/// ۸ فریم اخیر حداقل دو بار روشن/خاموش شده‌اند (سوسوزدن). جسم نارنجی ثابت،
/// چراغ ثابت یا ماشین قرمز در حال عبور سوسو نمی‌زنند و رد می‌شوند.
///
/// دود: ناحیهٔ خاکستری کم‌اشباع که نسبت به پس‌زمینهٔ کند تغییر کرده، چند
/// فریم پیاپی باقی مانده و کوچک نمی‌شود. این بخش آزمایشی است و خطای کاذب
/// بیشتری دارد (مثلاً لباس خاکستری یا مه).
class FireSmokeDetector {
  FireSmokeDetector({
    this.config = const FireSmokeConfig(),
    DetectionZone? zone,
  }) : zone = zone ?? const DetectionZone();

  final FireSmokeConfig config;
  final DetectionZone zone;

  int _w = 0, _h = 0;
  Uint8List? _hist;
  Float32List? _slowBg;
  Uint8List? _mask;
  int _maskCount = 0;
  int _frames = 0;
  final List<double> _smokeRatios = [];

  void reset() {
    _hist = null;
    _slowBg = null;
    _frames = 0;
    _smokeRatios.clear();
  }

  static final Uint8List _popcount = _buildPopcount();
  static Uint8List _buildPopcount() {
    final t = Uint8List(256);
    for (var i = 1; i < 256; i++) {
      t[i] = t[i >> 1] + (i & 1);
    }
    return t;
  }

  FireSmokeResult process(RgbFrame frame) {
    final f = frame.resizeBox(config.analysisWidth);
    final w = f.width, h = f.height;
    final n = w * h;

    if (_hist == null || _w != w || _h != h) {
      _w = w;
      _h = h;
      _hist = Uint8List(n);
      _slowBg = Float32List(n);
      final g = f.toGray();
      for (var i = 0; i < n; i++) {
        _slowBg![i] = g[i].toDouble();
      }
      _mask = zone.buildMask(w, h);
      _maskCount = _mask!.fold<int>(0, (a, b) => a + b);
      _frames = 0;
      _smokeRatios.clear();
    }
    if (_maskCount == 0) return const FireSmokeResult();

    final hist = _hist!;
    final bg = _slowBg!;
    final mask = _mask!;
    final rt = config.redThreshold;
    final rgb = f.rgb;

    var candidates = 0;
    var flicker = 0;
    var smokeCand = 0;
    var lightChangePixels = 0;

    final colCnt = Uint16List(w);
    final rowCnt = Uint16List(h);
    final smokeCol = Uint16List(w);
    final smokeRow = Uint16List(h);

    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        final p = i * 3;
        final r = rgb[p], g = rgb[p + 1], b = rgb[p + 2];
        final inMask = mask[i] == 1;

        // ---- آتش ----
        final cand = inMask && r > rt && r >= g && g > b && (r - b) >= 70
            ? 1
            : 0;
        final hv = ((hist[i] << 1) | cand) & 0xFF;
        hist[i] = hv;
        if (cand == 1) {
          candidates++;
          final trans = _popcount[(hv ^ (hv >> 1)) & 0x7F];
          if (trans >= 2) {
            flicker++;
            colCnt[x]++;
            rowCnt[y]++;
          }
        }

        // ---- دود ----
        final gray = (r * 77 + g * 150 + b * 29) >> 8;
        if (inMask) {
          final mx = r > g ? (r > b ? r : b) : (g > b ? g : b);
          final mn = r < g ? (r < b ? r : b) : (g < b ? g : b);
          final d = (gray - bg[i]).abs();
          if (d > 10) lightChangePixels++;
          if (mx - mn <= 18 &&
              gray >= 70 &&
              gray <= 215 &&
              d >= 10 &&
              d <= 55) {
            smokeCand++;
            smokeCol[x]++;
            smokeRow[y]++;
          }
        }
      }
    }

    _frames++;

    // ---- تصمیم آتش ----
    final fireScore = flicker / _maskCount;
    final flickerFraction = candidates == 0 ? 0.0 : flicker / candidates;
    final candRatio = candidates / _maskCount;
    final fire =
        _frames >= 6 &&
        fireScore >= config.minFireRatio &&
        flickerFraction >= 0.12 &&
        candRatio < 0.5;

    // ---- تصمیم دود ----
    final lightChange = lightChangePixels / _maskCount > 0.6;
    final smokeRatio = lightChange ? 0.0 : smokeCand / _maskCount;
    _smokeRatios.add(smokeRatio);
    if (_smokeRatios.length > 8) _smokeRatios.removeAt(0);

    var smoke = false;
    if (_frames >= 8 && _smokeRatios.length == 8) {
      final recent = _smokeRatios.sublist(5);
      final earlier = _smokeRatios.sublist(2, 5);
      final allAbove = _smokeRatios
          .sublist(2)
          .every((v) => v >= config.minSmokeRatio * 0.8);
      final rAvg = recent.reduce((a, b) => a + b) / recent.length;
      final eAvg = earlier.reduce((a, b) => a + b) / earlier.length;
      smoke = allAbove && rAvg >= config.minSmokeRatio && rAvg >= eAvg * 0.9;
    }

    // پس‌زمینهٔ کند: هر فریم کمی به تصویر فعلی نزدیک می‌شود؛
    // تغییر سراسری نور → بازنشانی کامل.
    final gAll = f.toGray();
    final rate = lightChange ? 1.0 : 0.02;
    for (var i = 0; i < n; i++) {
      bg[i] += (gAll[i] - bg[i]) * rate;
    }

    return FireSmokeResult(
      fire: fire,
      fireScore: fireScore,
      fireBbox: fire ? _bounds(colCnt, rowCnt, w, h) : null,
      smoke: smoke,
      smokeScore: smokeRatio,
      smokeBbox: smoke ? _bounds(smokeCol, smokeRow, w, h) : null,
    );
  }

  /// کادر اطراف ستون‌ها/ردیف‌هایی که حداقل ۲ پیکسل مثبت دارند.
  static NormRect? _bounds(Uint16List cols, Uint16List rows, int w, int h) {
    var x0 = -1, x1 = -1, y0 = -1, y1 = -1;
    for (var x = 0; x < w; x++) {
      if (cols[x] >= 2) {
        if (x0 < 0) x0 = x;
        x1 = x;
      }
    }
    for (var y = 0; y < h; y++) {
      if (rows[y] >= 2) {
        if (y0 < 0) y0 = y;
        y1 = y;
      }
    }
    if (x0 < 0 || y0 < 0) return null;
    return NormRect(x0 / w, y0 / h, (x1 + 1) / w, (y1 + 1) / h);
  }
}
