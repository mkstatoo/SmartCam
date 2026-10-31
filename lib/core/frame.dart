import 'dart:typed_data';

/// یک فریم رنگی کوچک‌شده (۳ بایت برای هر پیکسل، ردیف‌به‌ردیف، ترتیب R,G,B).
///
/// این کلاس هیچ وابستگی به Flutter ندارد تا هستهٔ تشخیص روی هر جایی
/// (موبایل، دسکتاپ، تست خط فرمان) اجرا و تست شود.
class RgbFrame {
  RgbFrame(this.width, this.height, this.rgb, {DateTime? time})
    : time = time ?? DateTime.now(),
      assert(width > 0 && height > 0),
      assert(rgb.length == width * height * 3);

  final int width;
  final int height;
  final Uint8List rgb;
  final DateTime time;

  /// ساخت فریم خالی با یک رنگ ثابت.
  factory RgbFrame.filled(int w, int h, int r, int g, int b, {DateTime? time}) {
    final data = Uint8List(w * h * 3);
    for (var i = 0; i < data.length; i += 3) {
      data[i] = r;
      data[i + 1] = g;
      data[i + 2] = b;
    }
    return RgbFrame(w, h, data, time: time);
  }

  /// تبدیل YUV420 (خروجی استاندارد پلاگین camera در اندروید) به RGB با
  /// نمونه‌برداری مستقیم در ابعاد هدف (سریع، بدون ساخت تصویر کامل).
  ///
  /// [yRowStride] و [uvRowStride] و [uvPixelStride] همان مقادیر Plane های
  /// CameraImage هستند. چرخش تصویر اعمال نمی‌شود (برای تشخیص حرکت لازم نیست).
  factory RgbFrame.fromYuv420({
    required int srcWidth,
    required int srcHeight,
    required Uint8List y,
    required Uint8List u,
    required Uint8List v,
    required int yRowStride,
    required int uvRowStride,
    required int uvPixelStride,
    required int targetWidth,
    DateTime? time,
  }) {
    final tw = targetWidth.clamp(1, srcWidth);
    final th = (srcHeight * tw / srcWidth).round().clamp(1, srcHeight);
    final out = Uint8List(tw * th * 3);
    var o = 0;
    for (var ty = 0; ty < th; ty++) {
      final sy = ((ty + 0.5) * srcHeight / th).floor().clamp(0, srcHeight - 1);
      for (var tx = 0; tx < tw; tx++) {
        final sx = ((tx + 0.5) * srcWidth / tw).floor().clamp(0, srcWidth - 1);
        final yy = y[sy * yRowStride + sx];
        final uvIndex = (sy >> 1) * uvRowStride + (sx >> 1) * uvPixelStride;
        final uu = u[uvIndex] - 128;
        final vv = v[uvIndex] - 128;
        // BT.601 (full range)
        final r = yy + 1.402 * vv;
        final g = yy - 0.344136 * uu - 0.714136 * vv;
        final b = yy + 1.772 * uu;
        out[o++] = r < 0 ? 0 : (r > 255 ? 255 : r.round());
        out[o++] = g < 0 ? 0 : (g > 255 ? 255 : g.round());
        out[o++] = b < 0 ? 0 : (b > 255 ? 255 : b.round());
      }
    }
    return RgbFrame(tw, th, out, time: time);
  }

  /// کوچک‌کردن با میانگین‌گیری جعبه‌ای (کیفیت بهتر از nearest برای کاهش نویز).
  RgbFrame resizeBox(int newWidth, {int? newHeight}) {
    final nw = newWidth.clamp(1, width);
    final nh = (newHeight ?? (height * nw / width).round()).clamp(1, height);
    if (nw == width && nh == height) return this;
    final out = Uint8List(nw * nh * 3);
    var o = 0;
    for (var y = 0; y < nh; y++) {
      final y0 = (y * height / nh).floor();
      final y1 = (((y + 1) * height / nh).ceil()).clamp(y0 + 1, height);
      for (var x = 0; x < nw; x++) {
        final x0 = (x * width / nw).floor();
        final x1 = (((x + 1) * width / nw).ceil()).clamp(x0 + 1, width);
        var sr = 0, sg = 0, sb = 0, n = 0;
        for (var yy = y0; yy < y1; yy++) {
          var i = (yy * width + x0) * 3;
          for (var xx = x0; xx < x1; xx++) {
            sr += rgb[i];
            sg += rgb[i + 1];
            sb += rgb[i + 2];
            i += 3;
            n++;
          }
        }
        out[o++] = sr ~/ n;
        out[o++] = sg ~/ n;
        out[o++] = sb ~/ n;
      }
    }
    return RgbFrame(nw, nh, out, time: time);
  }

  /// تصویر خاکستری (روشنایی) با وزن‌های استاندارد.
  Uint8List toGray() {
    final g = Uint8List(width * height);
    var j = 0;
    for (var i = 0; i < g.length; i++) {
      g[i] = (rgb[j] * 77 + rgb[j + 1] * 150 + rgb[j + 2] * 29) >> 8;
      j += 3;
    }
    return g;
  }

  /// تبدیل به RGBA برای نمایش در Flutter (ui.decodeImageFromPixels).
  Uint8List toRgba() {
    final out = Uint8List(width * height * 4);
    var j = 0, o = 0;
    for (var i = 0; i < width * height; i++) {
      out[o++] = rgb[j++];
      out[o++] = rgb[j++];
      out[o++] = rgb[j++];
      out[o++] = 255;
    }
    return out;
  }
}
