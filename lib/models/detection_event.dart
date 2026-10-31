import '../core/detection_engine.dart';

enum EventKind { motion, fire, smoke, offline, online }

String eventKindLabel(EventKind k) => switch (k) {
  EventKind.motion => 'حرکت',
  EventKind.fire => 'آتش‌سوزی',
  EventKind.smoke => 'دود',
  EventKind.offline => 'قطع ارتباط دوربین',
  EventKind.online => 'اتصال مجدد دوربین',
};

EventKind kindOf(DetectionType t) => switch (t) {
  DetectionType.motion => EventKind.motion,
  DetectionType.fire => EventKind.fire,
  DetectionType.smoke => EventKind.smoke,
};

/// رویدادهایی که باید آلارم بلند (آژیر) بزنند.
bool isCritical(EventKind k) => k == EventKind.fire || k == EventKind.smoke;

class DetectionEvent {
  DetectionEvent({
    required this.id,
    required this.cameraId,
    required this.cameraName,
    required this.kind,
    required this.time,
    this.score = 0,
    this.snapshotPath,
    this.acknowledged = false,
  });

  final String id;
  final String cameraId;
  final String cameraName;
  final EventKind kind;
  final DateTime time;
  final double score;
  final String? snapshotPath;
  bool acknowledged;

  Map<String, dynamic> toJson() => {
    'id': id,
    'cameraId': cameraId,
    'cameraName': cameraName,
    'kind': kind.name,
    'time': time.toIso8601String(),
    'score': score,
    'snapshotPath': snapshotPath,
    'ack': acknowledged,
  };

  factory DetectionEvent.fromJson(Map<String, dynamic> j) => DetectionEvent(
    id: j['id'] as String,
    cameraId: j['cameraId'] as String,
    cameraName: j['cameraName'] as String? ?? '',
    kind: EventKind.values.firstWhere(
      (e) => e.name == j['kind'],
      orElse: () => EventKind.motion,
    ),
    time: DateTime.parse(j['time'] as String),
    score: (j['score'] as num?)?.toDouble() ?? 0,
    snapshotPath: j['snapshotPath'] as String?,
    acknowledged: j['ack'] as bool? ?? false,
  );
}
