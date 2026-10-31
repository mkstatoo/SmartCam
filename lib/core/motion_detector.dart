import 'dart:typed_data';

import 'frame.dart';
import 'zone.dart';

class MotionConfig {
  const MotionConfig({
    this.sensitivity = 0.6,
    this.analysisWidth = 160,
    this.globalChangeRatio = 0.55,
  });

  /// ۰ (کم‌حساس) تا ۱ (بسیار حساس).
  final double sensitivity;

  /// عرض تصویر تحلیل؛ کوچک‌تر = سریع‌تر و کم‌نویزتر.
  final int analysisWidth;

  /// اگر بیش از این نسبت از پیکسل‌ها همزمان تغییر کنند، تغییر نور/اکسپوژر
  /// فرض می‌شود (نه حرکت) و پس‌زمینه بازنشانی می‌شود.
  final double globalChangeRatio;

  /// آستانهٔ اختلاف روشنایی هر پیکسل.
  double get pixelThreshold => _lerp(38, 14, sensitivity);

  /// کمترین تعداد بلوک ۸×۸ هم‌بند که باید فعال باشند.
  int get minBlocks => _lerp(5, 1, sensitivity).round().clamp(1, 99);

  static double _lerp(double a, double b, double t) =>
      a + (b - a) * t.clamp(0.0, 1.0);
}

class MotionResult {
  const MotionResult({
    required this.motion,
    required this.changedRatio,
    this.bbox,
    this.lightingChange = false,
    this.blocks = 0,
  });

  final bool motion;

  /// نسبت پیکسل‌های تغییرکرده به کل پیکسل‌های ناحیهٔ پایش.
  final double changedRatio;
  final NormRect? bbox;
  final bool lightingChange;

  /// اندازهٔ بزرگ‌ترین توده (به بلوک ۸×۸).
  final int blocks;
}

/// تشخیص حرکت با پس‌زمینهٔ تطبیقی:
/// خاکستری → محو ۳×۳ → اختلاف با پس‌زمینه → بلوک‌بندی ۸×۸ → بزرگ‌ترین توده.
class MotionDetector {
  MotionDetector({this.config = const MotionConfig(), DetectionZone? zone})
    : zone = zone ?? const DetectionZone();

  final MotionConfig config;
  final DetectionZone zone;

  static const int _block = 8;

  int _w = 0, _h = 0;
  Float32List? _bg;
  Uint8List? _mask;
  int _maskCount = 0;
  int _warmup = 0;

  void reset() {
    _bg = null;
    _warmup = 0;
  }

  MotionResult process(RgbFrame frame) {
    final f = frame.resizeBox(config.analysisWidth);
    final w = f.width, h = f.height;
    final gray = _blur(f.toGray(), w, h);

    if (_bg == null || _w != w || _h != h) {
      _w = w;
      _h = h;
      _bg = Float32List.fromList(gray.map((e) => e.toDouble()).toList());
      _mask = zone.buildMask(w, h);
      _maskCount = _mask!.fold<int>(0, (a, b) => a + b);
      _warmup = 0;
      return const MotionResult(motion: false, changedRatio: 0);
    }
    final bg = _bg!;
    final mask = _mask!;
    if (_maskCount == 0) {
      return const MotionResult(motion: false, changedRatio: 0);
    }

    final thr = config.pixelThreshold;
    final changed = Uint8List(w * h);
    var changedCount = 0;
    for (var i = 0; i < gray.length; i++) {
      if (mask[i] == 0) continue;
      if ((gray[i] - bg[i]).abs() > thr) {
        changed[i] = 1;
        changedCount++;
      }
    }
    final ratio = changedCount / _maskCount;

    // تغییر سراسری نور → بازنشانی پس‌زمینه، بدون اعلام حرکت.
    if (ratio > config.globalChangeRatio) {
      for (var i = 0; i < gray.length; i++) {
        bg[i] = gray[i].toDouble();
      }
      _warmup = 0;
      return MotionResult(
        motion: false,
        changedRatio: ratio,
        lightingChange: true,
      );
    }

    // به‌روزرسانی پس‌زمینه: پیکسل‌های ثابت سریع‌تر، پیکسل‌های تغییرکرده
    // آهسته (تا اشیای تازه‌ثابت‌شده بعد از مدتی جذب پس‌زمینه شوند).
    for (var i = 0; i < gray.length; i++) {
      final rate = changed[i] == 1 ? 0.01 : 0.06;
      bg[i] += (gray[i] - bg[i]) * rate;
    }

    // چند فریم اول بعد از شروع/بازنشانی فقط یادگیری است.
    if (_warmup < 2) {
      _warmup++;
      return MotionResult(motion: false, changedRatio: ratio);
    }

    // بلوک‌بندی و یافتن بزرگ‌ترین توده هم‌بند.
    final bw = (w / _block).ceil(), bh = (h / _block).ceil();
    final active = Uint8List(bw * bh);
    for (var by = 0; by < bh; by++) {
      for (var bx = 0; bx < bw; bx++) {
        var c = 0, t = 0;
        final y1 = ((by + 1) * _block).clamp(0, h);
        final x1 = ((bx + 1) * _block).clamp(0, w);
        for (var y = by * _block; y < y1; y++) {
          for (var x = bx * _block; x < x1; x++) {
            t++;
            c += changed[y * w + x];
          }
        }
        if (t > 0 && c / t >= 0.3) active[by * bw + bx] = 1;
      }
    }

    var bestSize = 0;
    var bMinX = 0, bMinY = 0, bMaxX = 0, bMaxY = 0;
    final seen = Uint8List(bw * bh);
    final stack = <int>[];
    for (var s = 0; s < active.length; s++) {
      if (active[s] == 0 || seen[s] == 1) continue;
      var size = 0;
      var minX = bw, minY = bh, maxX = 0, maxY = 0;
      stack
        ..clear()
        ..add(s);
      seen[s] = 1;
      while (stack.isNotEmpty) {
        final cur = stack.removeLast();
        final cx = cur % bw, cy = cur ~/ bw;
        size++;
        if (cx < minX) minX = cx;
        if (cx > maxX) maxX = cx;
        if (cy < minY) minY = cy;
        if (cy > maxY) maxY = cy;
        for (final n in [
          if (cx > 0) cur - 1,
          if (cx < bw - 1) cur + 1,
          if (cy > 0) cur - bw,
          if (cy < bh - 1) cur + bw,
        ]) {
          if (active[n] == 1 && seen[n] == 0) {
            seen[n] = 1;
            stack.add(n);
          }
        }
      }
      if (size > bestSize) {
        bestSize = size;
        bMinX = minX;
        bMinY = minY;
        bMaxX = maxX;
        bMaxY = maxY;
      }
    }

    final motion = bestSize >= config.minBlocks;
    return MotionResult(
      motion: motion,
      changedRatio: ratio,
      blocks: bestSize,
      bbox: motion
          ? NormRect(
              (bMinX * _block) / w,
              (bMinY * _block) / h,
              ((bMaxX + 1) * _block).clamp(0, w) / w,
              ((bMaxY + 1) * _block).clamp(0, h) / h,
            )
          : null,
    );
  }

  static Uint8List _blur(Uint8List g, int w, int h) {
    final out = Uint8List(g.length);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var s = 0, n = 0;
        for (var dy = -1; dy <= 1; dy++) {
          final yy = y + dy;
          if (yy < 0 || yy >= h) continue;
          for (var dx = -1; dx <= 1; dx++) {
            final xx = x + dx;
            if (xx < 0 || xx >= w) continue;
            s += g[yy * w + xx];
            n++;
          }
        }
        out[y * w + x] = s ~/ n;
      }
    }
    return out;
  }
}
