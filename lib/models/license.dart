/// محدودیت‌های هر طرح. مقدار واقعی را سرور اعلام می‌کند (قابل تغییر بدون آپدیت اپ)؛
/// این مقدارهای پیش‌فرض فقط برای زمانی است که هنوز پاسخی از سرور نیامده.
class Limits {
  const Limits({
    required this.maxCameras,
    required this.fireSmoke,
    required this.zones,
    required this.background,
    required this.maxEvents,
  });

  final int maxCameras;
  final bool fireSmoke;
  final bool zones;
  final bool background;
  final int maxEvents;

  static const Limits free = Limits(
    maxCameras: 2,
    fireSmoke: false,
    zones: false,
    background: false,
    maxEvents: 20,
  );

  static const Limits pro = Limits(
    maxCameras: 1000,
    fireSmoke: true,
    zones: true,
    background: true,
    maxEvents: 300,
  );

  factory Limits.fromJson(Map<String, dynamic>? j) {
    if (j == null) return free;
    return Limits(
      maxCameras: (j['max_cameras'] as num?)?.toInt() ?? free.maxCameras,
      fireSmoke: j['fire_smoke'] as bool? ?? false,
      zones: j['zones'] as bool? ?? false,
      background: j['background'] as bool? ?? false,
      maxEvents: (j['max_events'] as num?)?.toInt() ?? free.maxEvents,
    );
  }

  Map<String, dynamic> toJson() => {
    'max_cameras': maxCameras,
    'fire_smoke': fireSmoke,
    'zones': zones,
    'background': background,
    'max_events': maxEvents,
  };

  @override
  bool operator ==(Object o) =>
      o is Limits &&
      o.maxCameras == maxCameras &&
      o.fireSmoke == fireSmoke &&
      o.zones == zones &&
      o.background == background &&
      o.maxEvents == maxEvents;

  @override
  int get hashCode =>
      Object.hash(maxCameras, fireSmoke, zones, background, maxEvents);
}

/// آخرین مجوزی که سرور داده است.
class License {
  const License({
    required this.plan,
    required this.proUntil,
    required this.limits,
    required this.graceDays,
    required this.verifiedAt,
  });

  final String plan; // free | pro
  final int? proUntil; // ثانیه (UTC)، null = دائمی
  final Limits limits;
  final int graceDays;

  /// زمان محلی (ثانیه) که این مجوز از سرور رسیده است.
  final int verifiedAt;

  bool get isPro => plan == 'pro';

  factory License.fromServer(Map<String, dynamic> j, int nowSec) => License(
    plan: j['plan'] as String? ?? 'free',
    proUntil: (j['pro_until'] as num?)?.toInt(),
    limits: Limits.fromJson((j['limits'] as Map?)?.cast<String, dynamic>()),
    graceDays: (j['offline_grace_days'] as num?)?.toInt() ?? 30,
    verifiedAt: nowSec,
  );

  factory License.fromJson(Map<String, dynamic> j) => License(
    plan: j['plan'] as String? ?? 'free',
    proUntil: (j['pro_until'] as num?)?.toInt(),
    limits: Limits.fromJson((j['limits'] as Map?)?.cast<String, dynamic>()),
    graceDays: (j['grace'] as num?)?.toInt() ?? 30,
    verifiedAt: (j['verified_at'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'plan': plan,
    'pro_until': proUntil,
    'limits': limits.toJson(),
    'grace': graceDays,
    'verified_at': verifiedAt,
  };

  /// محدودیت مؤثر در همین لحظه، با در نظر گرفتن انقضا و مهلت آفلاین.
  /// قطع اینترنت در ایران رایج است، پس مهلت پیش‌فرض بلند (۳۰ روز) است.
  Limits effective(int nowSec) {
    if (!isPro) return limits;
    if (proUntil != null && nowSec > proUntil!) return Limits.free;
    final age = nowSec - verifiedAt;
    // ساعت گوشی را عقب برده‌اند یا مدت زیادی بی‌تماس با سرور بوده‌ایم
    if (age < -86400 || age > graceDays * 86400) return Limits.free;
    return limits;
  }
}

class AccountUser {
  const AccountUser({required this.id, required this.identifier, this.name = ''});
  final int id;
  final String identifier;
  final String name;

  factory AccountUser.fromJson(Map<String, dynamic> j) => AccountUser(
    id: (j['id'] as num).toInt(),
    identifier: j['identifier'] as String? ?? '',
    name: j['name'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {'id': id, 'identifier': identifier, 'name': name};
}

class DeviceInfoRow {
  const DeviceInfoRow({
    required this.id,
    required this.model,
    required this.appVersion,
    required this.lastSeen,
  });
  final int id;
  final String model;
  final String appVersion;
  final int lastSeen;

  factory DeviceInfoRow.fromJson(Map<String, dynamic> j) => DeviceInfoRow(
    id: (j['id'] as num).toInt(),
    model: j['model'] as String? ?? '',
    appVersion: j['app_version'] as String? ?? '',
    lastSeen: (j['last_seen'] as num?)?.toInt() ?? 0,
  );
}
