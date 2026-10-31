/// تنظیمات سراسری برنامه.
class AppSettings {
  AppSettings({
    this.motionSound = MotionSound.beep,
    this.sirenVolume = 1.0,
    this.vibrate = true,
    this.keepScreenOn = true,
    this.maxStoredEvents = 300,
    this.sirenAutoStopMinutes = 5,
  });

  /// صدای هشدار حرکت.
  MotionSound motionSound;

  /// بلندی آژیر آتش/دود (۰ تا ۱) — بلندی واقعی با صدای رسانهٔ گوشی هم تنظیم می‌شود.
  double sirenVolume;
  bool vibrate;

  /// روشن نگه‌داشتن صفحه هنگام پایش (برای پایداری بیشتر).
  bool keepScreenOn;
  int maxStoredEvents;

  /// آژیر بعد از این مدت (دقیقه) اگر کسی خاموشش نکرد، متوقف می‌شود.
  int sirenAutoStopMinutes;

  Map<String, dynamic> toJson() => {
    'motionSound': motionSound.name,
    'sirenVolume': sirenVolume,
    'vibrate': vibrate,
    'keepScreenOn': keepScreenOn,
    'maxStoredEvents': maxStoredEvents,
    'sirenAutoStopMinutes': sirenAutoStopMinutes,
  };

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
    motionSound: MotionSound.values.firstWhere(
      (e) => e.name == j['motionSound'],
      orElse: () => MotionSound.beep,
    ),
    sirenVolume: (j['sirenVolume'] as num?)?.toDouble() ?? 1.0,
    vibrate: j['vibrate'] as bool? ?? true,
    keepScreenOn: j['keepScreenOn'] as bool? ?? true,
    maxStoredEvents: j['maxStoredEvents'] as int? ?? 300,
    sirenAutoStopMinutes: j['sirenAutoStopMinutes'] as int? ?? 5,
  );
}

enum MotionSound { silent, beep, siren }

String motionSoundLabel(MotionSound s) => switch (s) {
  MotionSound.silent => 'بی‌صدا (فقط اعلان)',
  MotionSound.beep => 'بوق کوتاه',
  MotionSound.siren => 'آژیر',
};
