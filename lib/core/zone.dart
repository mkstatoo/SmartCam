import 'dart:typed_data';

/// مستطیل نرمال‌شده (مختصات ۰ تا ۱ نسبت به عرض و ارتفاع تصویر).
class NormRect {
  const NormRect(this.left, this.top, this.right, this.bottom);

  final double left, top, right, bottom;

  double get width => right - left;
  double get height => bottom - top;

  Map<String, dynamic> toJson() => {
    'l': left,
    't': top,
    'r': right,
    'b': bottom,
  };

  factory NormRect.fromJson(Map<String, dynamic> j) => NormRect(
    (j['l'] as num).toDouble(),
    (j['t'] as num).toDouble(),
    (j['r'] as num).toDouble(),
    (j['b'] as num).toDouble(),
  );

  @override
  String toString() => 'NormRect($left,$top,$right,$bottom)';
}

/// ناحیهٔ مورد پایش: اگر [include] خالی باشد کل تصویر پایش می‌شود؛
/// نواحی [exclude] (مثلاً درخت متحرک یا خیابان) همیشه نادیده گرفته می‌شوند.
class DetectionZone {
  const DetectionZone({this.include = const [], this.exclude = const []});

  final List<NormRect> include;
  final List<NormRect> exclude;

  bool get isFullFrame => include.isEmpty && exclude.isEmpty;

  /// ماسک ۰/۱ با ابعاد داده‌شده (۱ = پیکسل پایش می‌شود).
  Uint8List buildMask(int w, int h) {
    final m = Uint8List(w * h);
    if (include.isEmpty) {
      m.fillRange(0, m.length, 1);
    } else {
      for (final r in include) {
        _paint(m, w, h, r, 1);
      }
    }
    for (final r in exclude) {
      _paint(m, w, h, r, 0);
    }
    return m;
  }

  static void _paint(Uint8List m, int w, int h, NormRect r, int v) {
    final x0 = (r.left.clamp(0.0, 1.0) * w).floor();
    final x1 = (r.right.clamp(0.0, 1.0) * w).ceil().clamp(0, w);
    final y0 = (r.top.clamp(0.0, 1.0) * h).floor();
    final y1 = (r.bottom.clamp(0.0, 1.0) * h).ceil().clamp(0, h);
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        m[y * w + x] = v;
      }
    }
  }

  Map<String, dynamic> toJson() => {
    'include': include.map((e) => e.toJson()).toList(),
    'exclude': exclude.map((e) => e.toJson()).toList(),
  };

  factory DetectionZone.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const DetectionZone();
    List<NormRect> rd(String k) => ((j[k] as List?) ?? const [])
        .map((e) => NormRect.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    return DetectionZone(include: rd('include'), exclude: rd('exclude'));
  }
}
