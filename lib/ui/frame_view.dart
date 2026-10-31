import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/frame.dart';
import '../core/zone.dart';

/// نمایش یک RgbFrame (و در صورت نیاز ناحیه‌های پایش/مستثنی روی آن).
class FrameView extends StatefulWidget {
  const FrameView({
    super.key,
    required this.source,
    this.fit = BoxFit.cover,
    this.zone,
    this.placeholder,
  });

  final ValueNotifier<RgbFrame?> source;
  final BoxFit fit;
  final DetectionZone? zone;
  final Widget? placeholder;

  @override
  State<FrameView> createState() => _FrameViewState();
}

class _FrameViewState extends State<FrameView> {
  ui.Image? _image;
  bool _decoding = false;

  @override
  void initState() {
    super.initState();
    widget.source.addListener(_onFrame);
    _onFrame();
  }

  @override
  void didUpdateWidget(covariant FrameView old) {
    super.didUpdateWidget(old);
    if (old.source != widget.source) {
      old.source.removeListener(_onFrame);
      widget.source.addListener(_onFrame);
      _onFrame();
    }
  }

  @override
  void dispose() {
    widget.source.removeListener(_onFrame);
    _image?.dispose();
    super.dispose();
  }

  void _onFrame() {
    final f = widget.source.value;
    if (f == null || _decoding) return;
    _decoding = true;
    ui.decodeImageFromPixels(
      f.toRgba(),
      f.width,
      f.height,
      ui.PixelFormat.rgba8888,
      (img) {
        _decoding = false;
        if (!mounted) {
          img.dispose();
          return;
        }
        setState(() {
          _image?.dispose();
          _image = img;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final img = _image;
    if (img == null) {
      return widget.placeholder ??
          const ColoredBox(
            color: Colors.black,
            child: Center(
              child: Icon(Icons.videocam_off, color: Colors.white24),
            ),
          );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        RawImage(image: img, fit: widget.fit),
        if (widget.zone != null && !widget.zone!.isFullFrame)
          CustomPaint(painter: _ZonePainter(widget.zone!)),
      ],
    );
  }
}

class _ZonePainter extends CustomPainter {
  _ZonePainter(this.zone);
  final DetectionZone zone;

  @override
  void paint(Canvas canvas, Size s) {
    Rect r(NormRect n) => Rect.fromLTRB(
      n.left * s.width,
      n.top * s.height,
      n.right * s.width,
      n.bottom * s.height,
    );
    for (final n in zone.include) {
      canvas.drawRect(
        r(n),
        Paint()..color = Colors.greenAccent.withOpacity(.18),
      );
      canvas.drawRect(
        r(n),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.greenAccent,
      );
    }
    for (final n in zone.exclude) {
      canvas.drawRect(r(n), Paint()..color = Colors.redAccent.withOpacity(.25));
      canvas.drawRect(
        r(n),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.redAccent,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ZonePainter old) => old.zone != zone;
}
