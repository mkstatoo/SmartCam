import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// نگه‌داشتن پایش در پس‌زمینه.
///
/// اندروید: سرویس پیش‌زمینه (با اعلان دائمی) + قفل بیدار نگه‌داشتن CPU/Wi-Fi.
/// iOS: سیستم‌عامل اجازهٔ اجرای دائمی پردازش تصویر در پس‌زمینه را نمی‌دهد؛
/// برای پایش واقعی، برنامه باید باز و صفحه روشن بماند (wakelock).
class BackgroundService {
  static bool _inited = false;

  static void init() {
    if (_inited || !Platform.isAndroid) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'monitor_service',
        channelName: 'پایش دوربین‌ها',
        channelDescription: 'برنامه در حال پایش دوربین‌هاست',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    _inited = true;
  }

  /// [foreground] = false (نسخهٔ رایگان): سرویس پیش‌زمینه راه نمی‌افتد و پایش فقط
  /// تا وقتی برنامه باز است ادامه دارد.
  static Future<void> start({
    required bool keepScreenOn,
    bool foreground = true,
  }) async {
    if (keepScreenOn) await WakelockPlus.enable();
    if (!Platform.isAndroid || !foreground) return;
    init();
    if (await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.startService(
      notificationTitle: 'کارآگاه دوربین',
      notificationText: 'پایش دوربین‌ها فعال است',
    );
  }

  static Future<void> stop() async {
    await WakelockPlus.disable();
    if (!Platform.isAndroid) return;
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }

  /// باز کردن صفحهٔ «بهینه‌سازی باتری» سیستم (مهم برای گوشی‌های شیائومی/سامسونگ/…).
  /// کاربر خودش برنامه را از لیست انتخاب و «بدون محدودیت» می‌کند. این روش به مجوز
  /// REQUEST_IGNORE_BATTERY_OPTIMIZATIONS نیاز ندارد (که در گوگل‌پلی محدود است).
  static Future<void> openBatterySettings() async {
    if (!Platform.isAndroid) return;
    try {
      await FlutterForegroundTask.openIgnoreBatteryOptimizationSettings();
    } catch (_) {}
  }
}
