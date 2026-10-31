import 'dart:convert';

import '../core/detection_engine.dart';
import '../core/zone.dart';

/// نوع منبع تصویر.
enum SourceType {
  /// RTSP / RTMP / HLS / هر آدرسی که مدیاکیت بتواند باز کند.
  stream,

  /// جریان MJPEG روی HTTP (بسیاری از دوربین‌های ارزان، اپ‌های «دوربین IP» گوشی).
  mjpeg,

  /// عکس لحظه‌ای (JPEG) که هر چند ثانیه دریافت می‌شود.
  snapshot,

  /// دوربین همین گوشی.
  phone,
}

String sourceTypeLabel(SourceType t) => switch (t) {
  SourceType.stream => 'RTSP / جریان ویدیویی',
  SourceType.mjpeg => 'MJPEG روی HTTP',
  SourceType.snapshot => 'عکس لحظه‌ای (HTTP)',
  SourceType.phone => 'دوربین این گوشی',
};

class CameraConfig {
  CameraConfig({
    required this.id,
    required this.name,
    required this.type,
    this.url = '',
    this.username = '',
    this.password = '',
    this.enabled = true,
    this.fps = 2,
    this.motionEnabled = true,
    this.fireEnabled = true,
    this.smokeEnabled = true,
    this.motionSensitivity = 0.6,
    this.fireSensitivity = 0.6,
    this.smokeSensitivity = 0.5,
    this.zone = const DetectionZone(),
    this.phoneCameraIndex = 0,
  });

  final String id;
  String name;
  SourceType type;
  String url;

  /// نام کاربری/رمز: در حافظهٔ امن ذخیره می‌شوند، نه در JSON اصلی.
  String username;
  String password;

  bool enabled;

  /// تعداد فریم تحلیل‌شده در ثانیه (۱ تا ۵).
  double fps;

  bool motionEnabled, fireEnabled, smokeEnabled;
  double motionSensitivity, fireSensitivity, smokeSensitivity;
  DetectionZone zone;
  int phoneCameraIndex;

  /// [allowFireSmoke] و [allowZones] از مجوز کاربر می‌آیند (نسخهٔ رایگان: false).
  EngineConfig toEngineConfig({
    bool allowFireSmoke = true,
    bool allowZones = true,
  }) => EngineConfig(
    motionEnabled: motionEnabled,
    fireEnabled: fireEnabled && allowFireSmoke,
    smokeEnabled: smokeEnabled && allowFireSmoke,
    motionSensitivity: motionSensitivity,
    fireSensitivity: fireSensitivity,
    smokeSensitivity: smokeSensitivity,
    zone: allowZones ? zone : const DetectionZone(),
  );

  CameraConfig copy() => CameraConfig.fromJson(toJson(includeSecrets: true));

  Map<String, dynamic> toJson({bool includeSecrets = false}) => {
    'id': id,
    'name': name,
    'type': type.name,
    'url': url,
    if (includeSecrets) 'username': username,
    if (includeSecrets) 'password': password,
    'enabled': enabled,
    'fps': fps,
    'motionEnabled': motionEnabled,
    'fireEnabled': fireEnabled,
    'smokeEnabled': smokeEnabled,
    'motionSensitivity': motionSensitivity,
    'fireSensitivity': fireSensitivity,
    'smokeSensitivity': smokeSensitivity,
    'zone': zone.toJson(),
    'phoneCameraIndex': phoneCameraIndex,
  };

  factory CameraConfig.fromJson(Map<String, dynamic> j) => CameraConfig(
    id: j['id'] as String,
    name: j['name'] as String? ?? 'دوربین',
    type: SourceType.values.firstWhere(
      (e) => e.name == j['type'],
      orElse: () => SourceType.stream,
    ),
    url: j['url'] as String? ?? '',
    username: j['username'] as String? ?? '',
    password: j['password'] as String? ?? '',
    enabled: j['enabled'] as bool? ?? true,
    fps: (j['fps'] as num?)?.toDouble() ?? 2,
    motionEnabled: j['motionEnabled'] as bool? ?? true,
    fireEnabled: j['fireEnabled'] as bool? ?? true,
    smokeEnabled: j['smokeEnabled'] as bool? ?? true,
    motionSensitivity: (j['motionSensitivity'] as num?)?.toDouble() ?? 0.6,
    fireSensitivity: (j['fireSensitivity'] as num?)?.toDouble() ?? 0.6,
    smokeSensitivity: (j['smokeSensitivity'] as num?)?.toDouble() ?? 0.5,
    zone: DetectionZone.fromJson((j['zone'] as Map?)?.cast<String, dynamic>()),
    phoneCameraIndex: j['phoneCameraIndex'] as int? ?? 0,
  );

  static String encodeList(List<CameraConfig> l) =>
      jsonEncode(l.map((e) => e.toJson()).toList());

  static List<CameraConfig> decodeList(String s) => (jsonDecode(s) as List)
      .map((e) => CameraConfig.fromJson((e as Map).cast<String, dynamic>()))
      .toList();

  /// آدرس همراه با نام کاربری/رمز، برای بازکردن در پخش‌کننده.
  /// (برای RTSP اگر خود آدرس اطلاعات ورود نداشته باشد اضافه می‌شود.)
  String get effectiveUrl {
    if (username.isEmpty) return url;
    final u = Uri.tryParse(url);
    if (u == null || u.userInfo.isNotEmpty || !u.hasScheme) return url;
    if (type == SourceType.mjpeg || type == SourceType.snapshot) return url;
    return u
        .replace(
          userInfo:
              '${Uri.encodeComponent(username)}:${Uri.encodeComponent(password)}',
        )
        .toString();
  }
}
