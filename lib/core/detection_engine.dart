import 'fire_smoke_detector.dart';
import 'frame.dart';
import 'motion_detector.dart';
import 'zone.dart';

enum DetectionType { motion, fire, smoke }

/// رویداد نهایی (بعد از تأیید چندفریمی و اعمال زمان خنک‌شدن).
class DetectionSignal {
  const DetectionSignal({
    required this.type,
    required this.time,
    required this.score,
    this.bbox,
  });

  final DetectionType type;
  final DateTime time;
  final double score;
  final NormRect? bbox;
}

class EngineConfig {
  const EngineConfig({
    this.motionEnabled = true,
    this.fireEnabled = true,
    this.smokeEnabled = true,
    this.motionSensitivity = 0.6,
    this.fireSensitivity = 0.6,
    this.smokeSensitivity = 0.5,
    this.zone = const DetectionZone(),
    this.motionConfirmFrames = 2,
    this.fireConfirmFrames = 3,
    this.smokeConfirmFrames = 2,
    this.motionCooldown = const Duration(seconds: 30),
    this.fireCooldown = const Duration(seconds: 15),
    this.smokeCooldown = const Duration(seconds: 30),
  });

  final bool motionEnabled, fireEnabled, smokeEnabled;
  final double motionSensitivity, fireSensitivity, smokeSensitivity;
  final DetectionZone zone;
  final int motionConfirmFrames, fireConfirmFrames, smokeConfirmFrames;
  final Duration motionCooldown, fireCooldown, smokeCooldown;
}

/// ترکیب تشخیص حرکت/آتش/دود + فیلتر زمانی:
/// یک رویداد فقط وقتی صادر می‌شود که چند فریم پیاپی مثبت باشد و از رویداد
/// قبلیِ همان نوع، حداقل به اندازهٔ زمان خنک‌شدن گذشته باشد.
/// زمان از خود فریم (`frame.time`) خوانده می‌شود تا تست‌پذیر باشد.
class DetectionEngine {
  DetectionEngine(this.config)
    : _motion = MotionDetector(
        config: MotionConfig(sensitivity: config.motionSensitivity),
        zone: config.zone,
      ),
      _fire = FireSmokeDetector(
        config: FireSmokeConfig(
          fireSensitivity: config.fireSensitivity,
          smokeSensitivity: config.smokeSensitivity,
        ),
        zone: config.zone,
      );

  final EngineConfig config;
  final MotionDetector _motion;
  final FireSmokeDetector _fire;

  final Map<DetectionType, int> _streak = {
    for (final t in DetectionType.values) t: 0,
  };
  final Map<DetectionType, DateTime?> _lastEmit = {
    for (final t in DetectionType.values) t: null,
  };

  /// آخرین نتیجهٔ خام (برای نمایش وضعیت در رابط کاربری).
  MotionResult? lastMotion;
  FireSmokeResult? lastFireSmoke;

  void reset() {
    _motion.reset();
    _fire.reset();
    for (final t in DetectionType.values) {
      _streak[t] = 0;
    }
  }

  List<DetectionSignal> process(RgbFrame frame) {
    final out = <DetectionSignal>[];
    final now = frame.time;

    if (config.motionEnabled) {
      final r = _motion.process(frame);
      lastMotion = r;
      _handle(
        out,
        DetectionType.motion,
        r.motion,
        now,
        r.changedRatio,
        r.bbox,
        config.motionConfirmFrames,
        config.motionCooldown,
      );
    }
    if (config.fireEnabled || config.smokeEnabled) {
      final r = _fire.process(frame);
      lastFireSmoke = r;
      if (config.fireEnabled) {
        _handle(
          out,
          DetectionType.fire,
          r.fire,
          now,
          r.fireScore,
          r.fireBbox,
          config.fireConfirmFrames,
          config.fireCooldown,
        );
      }
      if (config.smokeEnabled) {
        _handle(
          out,
          DetectionType.smoke,
          r.smoke,
          now,
          r.smokeScore,
          r.smokeBbox,
          config.smokeConfirmFrames,
          config.smokeCooldown,
        );
      }
    }
    return out;
  }

  void _handle(
    List<DetectionSignal> out,
    DetectionType type,
    bool positive,
    DateTime now,
    double score,
    NormRect? bbox,
    int confirm,
    Duration cd,
  ) {
    if (!positive) {
      _streak[type] = 0;
      return;
    }
    final s = (_streak[type] ?? 0) + 1;
    _streak[type] = s;
    if (s < confirm) return;
    final last = _lastEmit[type];
    if (last != null && now.difference(last) < cd) return;
    _lastEmit[type] = now;
    out.add(DetectionSignal(type: type, time: now, score: score, bbox: bbox));
  }
}
