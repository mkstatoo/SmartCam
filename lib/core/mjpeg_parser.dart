import 'dart:typed_data';

/// استخراج فریم‌های JPEG از جریان خام HTTP multipart (MJPEG).
///
/// قطعه‌های ورودی می‌توانند در هر نقطه‌ای بریده شده باشند؛ پارسر با جست‌وجوی
/// نشانگر شروع (FF D8) و پایان (FF D9) فریم‌ها را جدا می‌کند و به هدر
/// multipart وابسته نیست، بنابراین با دوربین‌های مختلف کار می‌کند.
class MjpegParser {
  MjpegParser({this.maxFrameBytes = 8 * 1024 * 1024});

  final int maxFrameBytes;

  Uint8List _buf = Uint8List(64 * 1024);
  int _len = 0;

  /// بافر را خالی می‌کند (مثلاً هنگام اتصال مجدد).
  void reset() => _len = 0;

  /// یک قطعه داده را اضافه می‌کند و فریم‌های کامل‌شده را برمی‌گرداند.
  List<Uint8List> add(List<int> chunk) {
    _ensure(_len + chunk.length);
    _buf.setRange(_len, _len + chunk.length, chunk);
    _len += chunk.length;

    final frames = <Uint8List>[];
    var pos = 0;
    while (true) {
      final soi = _find(0xFF, 0xD8, pos);
      if (soi < 0) {
        // چیزی شبیه شروع فریم نیست؛ فقط آخرین بایت ممکن است نیمهٔ FF D8 باشد.
        pos = _len > 0 ? _len - 1 : 0;
        break;
      }
      final eoi = _find(0xFF, 0xD9, soi + 2);
      if (eoi < 0) {
        if (_len - soi > maxFrameBytes) {
          // فریم غیرمعتبر/بیش از حد بزرگ؛ دور انداخته می‌شود.
          pos = _len;
        } else {
          pos = soi;
        }
        break;
      }
      frames.add(Uint8List.fromList(_buf.sublist(soi, eoi + 2)));
      pos = eoi + 2;
    }

    if (pos > 0) {
      final remain = _len - pos;
      if (remain > 0) _buf.setRange(0, remain, _buf, pos);
      _len = remain;
    }
    return frames;
  }

  int _find(int a, int b, int from) {
    for (var i = from; i < _len - 1; i++) {
      if (_buf[i] == a && _buf[i + 1] == b) return i;
    }
    return -1;
  }

  void _ensure(int need) {
    if (need <= _buf.length) return;
    var n = _buf.length;
    while (n < need) {
      n *= 2;
    }
    final nb = Uint8List(n);
    nb.setRange(0, _len, _buf);
    _buf = nb;
  }
}
