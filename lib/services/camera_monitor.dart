import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../core/detection_engine.dart';
import '../core/frame.dart';
import '../core/zone.dart';
import '../models/camera_config.dart';
import '../models/detection_event.dart';
import '../sources/frame_source.dart';
import '../sources/source_factory.dart';
import 'account_manager.dart';

enum MonitorState { stopped, connecting, live, error }

/// مسئول یک دوربین: منبع تصویر ← موتور تشخیص ← رویداد.
/// اتصال را زنده نگه می‌دارد (تلاش مجدد با فاصلهٔ فزاینده) و قطع طولانی
/// دوربین را هم به‌عنوان رویداد اعلام می‌کند.
class CameraMonitor {
  CameraMonitor(
    this.config, {
    required this.onEvent,
    required this.saveSnapshot,
  });

  CameraConfig config;
  final void Function(DetectionEvent event) onEvent;
  final Future<String> Function(String id, List<int> jpeg) saveSnapshot;

  final ValueNotifier<MonitorState> state = ValueNotifier(MonitorState.stopped);
  final ValueNotifier<RgbFrame?> lastFrame = ValueNotifier(null);
  final ValueNotifier<String?> error = ValueNotifier(null);

  /// آخرین نتیجهٔ خام تشخیص برای نمایش «نوار فعالیت» در کاشی دوربین.
  final ValueNotifier<double> motionLevel = ValueNotifier(0);

  FrameSource? _source;
  StreamSubscription<RgbFrame>? _fSub;
  StreamSubscription<SourceStatus>? _sSub;
  DetectionEngine? _engine;
  Timer? _watchdog;
  Timer? _retry;
  int _retries = 0;
  DateTime _lastFrameAt = DateTime.now();
  DateTime? _downSince;
  bool _offlineReported = false;
  bool _running = false;

  static const Duration _offlineAfter = Duration(seconds: 45);

  bool get running => _running;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    final lim = account.limits;
    _engine = DetectionEngine(
      config.toEngineConfig(allowFireSmoke: lim.fireSmoke, allowZones: lim.zones),
    );
    await _connect();
    _watchdog = Timer.periodic(const Duration(seconds: 5), (_) => _check());
  }

  Future<void> stop() async {
    _running = false;
    _watchdog?.cancel();
    _retry?.cancel();
    await _teardown();
    state.value = MonitorState.stopped;
  }

  /// بعد از ویرایش تنظیمات فراخوانی می‌شود.
  Future<void> restart(CameraConfig newConfig) async {
    final was = _running;
    await stop();
    config = newConfig;
    if (was && newConfig.enabled) await start();
  }

  Future<void> _connect() async {
    if (!_running) return;
    await _teardown();
    state.value = MonitorState.connecting;
    _engine?.reset();
    final src = createSource(config);
    _source = src;
    _fSub = src.frames.listen(_onFrame);
    _sSub = src.status.listen(_onStatus);
    _lastFrameAt = DateTime.now();
    try {
      await src.start();
    } catch (e) {
      _fail('$e');
    }
  }

  Future<void> _teardown() async {
    await _fSub?.cancel();
    await _sSub?.cancel();
    _fSub = _sSub = null;
    final s = _source;
    _source = null;
    try {
      await s?.stop();
    } catch (_) {}
  }

  void _onStatus(SourceStatus s) {
    if (s.state == SourceState.error) _fail(s.message ?? 'خطای نامشخص');
  }

  void _fail(String msg) {
    if (!_running) return;
    error.value = msg;
    state.value = MonitorState.error;
    _downSince ??= DateTime.now();
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (_retry?.isActive ?? false) return;
    _retries++;
    final secs = (_retries * 5).clamp(5, 60);
    _retry = Timer(Duration(seconds: secs), () {
      _retry = null;
      _connect();
    });
  }

  void _check() {
    if (!_running) return;
    final now = DateTime.now();
    if (state.value == MonitorState.live &&
        now.difference(_lastFrameAt) > const Duration(seconds: 20)) {
      _fail('تصویر متوقف شد');
    }
    final down = _downSince;
    if (down != null &&
        !_offlineReported &&
        now.difference(down) > _offlineAfter) {
      _offlineReported = true;
      _emit(EventKind.offline, 0, null);
    }
  }

  void _onFrame(RgbFrame frame) {
    if (!_running) return;
    _lastFrameAt = DateTime.now();
    if (state.value != MonitorState.live) {
      state.value = MonitorState.live;
      error.value = null;
      _retries = 0;
      if (_offlineReported) {
        _emit(EventKind.online, 0, null);
      }
      _offlineReported = false;
      _downSince = null;
    }
    lastFrame.value = frame;

    final engine = _engine;
    if (engine == null) return;
    final signals = engine.process(frame);
    final m = engine.lastMotion;
    motionLevel.value = m == null ? 0 : (m.changedRatio * 8).clamp(0.0, 1.0);

    for (final s in signals) {
      _emit(kindOf(s.type), s.score, s.bbox, frame: frame);
    }
  }

  Future<void> _emit(
    EventKind kind,
    double score,
    NormRect? bbox, {
    RgbFrame? frame,
  }) async {
    final id = '${DateTime.now().microsecondsSinceEpoch}_${config.id}';
    String? path;
    final f = frame ?? lastFrame.value;
    if (f != null) {
      try {
        path = await saveSnapshot(id, _encode(f, bbox, kind));
      } catch (_) {}
    }
    onEvent(
      DetectionEvent(
        id: id,
        cameraId: config.id,
        cameraName: config.name,
        kind: kind,
        time: DateTime.now(),
        score: score,
        snapshotPath: path,
      ),
    );
  }

  /// JPEG با کادر دور ناحیهٔ تشخیص‌داده‌شده.
  Uint8List _encode(RgbFrame f, NormRect? bbox, EventKind kind) {
    final image = img.Image.fromBytes(
      width: f.width,
      height: f.height,
      bytes: Uint8List.fromList(f.rgb).buffer,
      numChannels: 3,
    );
    if (bbox != null) {
      final color = switch (kind) {
        EventKind.fire => img.ColorRgb8(255, 60, 30),
        EventKind.smoke => img.ColorRgb8(255, 200, 0),
        _ => img.ColorRgb8(60, 220, 120),
      };
      img.drawRect(
        image,
        x1: (bbox.left * f.width).round(),
        y1: (bbox.top * f.height).round(),
        x2: (bbox.right * f.width).round().clamp(0, f.width - 1),
        y2: (bbox.bottom * f.height).round().clamp(0, f.height - 1),
        color: color,
        thickness: 2,
      );
    }
    return Uint8List.fromList(img.encodeJpg(image, quality: 82));
  }

  void dispose() {
    state.dispose();
    lastFrame.dispose();
    error.dispose();
    motionLevel.dispose();
  }
}
