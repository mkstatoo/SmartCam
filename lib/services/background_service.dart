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

  static Future<void> start({required bool keepScreenOn}) async {
    if (keepScreenOn) await WakelockPlus.enable();
    if (!Platform.isAndroid) return;
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

  /// درخواست معافیت از بهینه‌سازی باتری (مهم برای گوشی‌های شیائومی/سامسونگ/…).
  static Future<void> requestBatteryExemption() async {
    if (!Platform.isAndroid) return;
    try {
      if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }
    } catch (_) {}
  }
}
