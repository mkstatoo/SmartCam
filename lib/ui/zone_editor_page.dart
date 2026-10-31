import 'package:flutter/material.dart';

import '../core/frame.dart';
import '../core/zone.dart';
import 'frame_view.dart';

/// ویرایش ناحیهٔ پایش: با کشیدن انگشت روی تصویر مستطیل بکشید.
/// سبز = فقط همین ناحیه‌ها پایش شود، قرمز = این ناحیه‌ها نادیده گرفته شود.
class ZoneEditorPage extends StatefulWidget {
  const ZoneEditorPage({super.key, required this.initial, this.frame});
  final DetectionZone initial;
  final RgbFrame? frame;

  @override
  State<ZoneEditorPage> createState() => _ZoneEditorPageState();
}

class _ZoneEditorPageState extends State<ZoneEditorPage> {
  late final List<NormRect> _include = [...widget.initial.include];
  late final List<NormRect> _exclude = [...widget.initial.exclude];
  late final ValueNotifier<RgbFrame?> _frame = ValueNotifier(widget.frame);
  bool _excludeMode = true;
  Offset? _start, _cur;

  DetectionZone get _zone =>
      DetectionZone(include: List.of(_include), exclude: List.of(_exclude));

  @override
  void dispose() {
    _frame.dispose();
    super.dispose();
  }

  NormRect? _drag(Size s) {
    if (_start == null || _cur == null) return null;
    final a = _start!, b = _cur!;
    double nx(double v) => (v / s.width).clamp(0.0, 1.0);
    double ny(double v) => (v / s.height).clamp(0.0, 1.0);
    return NormRect(
      nx(a.dx < b.dx ? a.dx : b.dx),
      ny(a.dy < b.dy ? a.dy : b.dy),
      nx(a.dx < b.dx ? b.dx : a.dx),
      ny(a.dy < b.dy ? b.dy : a.dy),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ratio = widget.frame == null
        ? 16 / 9
        : widget.frame!.width / widget.frame!.height;
    return Scaffold(
      appBar: AppBar(
        title: const Text('ناحیهٔ پایش'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_zone),
            child: const Text('تأیید'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.block, color: Colors.redAccent),
                  label: Text('نادیده بگیر'),
                ),
                ButtonSegment(
                  value: false,
                  icon: Icon(
                    Icons.check_box_outlined,
                    color: Colors.greenAccent,
                  ),
                  label: Text('فقط پایش کن'),
                ),
              ],
              selected: {_excludeMode},
              onSelectionChanged: (s) => setState(() => _excludeMode = s.first),
            ),
          ),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: ratio,
                child: LayoutBuilder(
                  builder: (context, c) {
                    final size = Size(c.maxWidth, c.maxHeight);
                    final drag = _drag(size);
                    return GestureDetector(
                      onPanStart: (d) => setState(() {
                        _start = d.localPosition;
                        _cur = d.localPosition;
                      }),
                      onPanUpdate: (d) =>
                          setState(() => _cur = d.localPosition),
                      onPanEnd: (_) => setState(() {
                        final r = _drag(size);
                        if (r != null && r.width > 0.03 && r.height > 0.03) {
                          (_excludeMode ? _exclude : _include).add(r);
                        }
                        _start = _cur = null;
                      }),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          FrameView(
                            source: _frame,
                            fit: BoxFit.fill,
                            zone: _zone,
                          ),
                          if (drag != null)
                            Positioned(
                              left: drag.left * size.width,
                              top: drag.top * size.height,
                              width: drag.width * size.width,
                              height: drag.height * size.height,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: _excludeMode
                                        ? Colors.redAccent
                                        : Colors.greenAccent,
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'ناحیهٔ سبز: ${_include.length}   ناحیهٔ قرمز: ${_exclude.length}\n'
                    'اگر هیچ ناحیهٔ سبزی نکشید، کل تصویر پایش می‌شود.',
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => setState(() {
                    if (_excludeMode
                        ? _exclude.isNotEmpty
                        : _include.isNotEmpty) {
                      (_excludeMode ? _exclude : _include).removeLast();
                    }
                  }),
                  icon: const Icon(Icons.undo),
                  label: const Text('برگردان'),
                ),
                TextButton.icon(
                  onPressed: () => setState(() {
                    _include.clear();
                    _exclude.clear();
                  }),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('پاک کردن'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
