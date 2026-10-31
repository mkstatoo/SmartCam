import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/detection_event.dart';

/// اعلان‌های سیستمی (برای وقتی که برنامه در پس‌زمینه است یا صفحه خاموش).
class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;
  int _nextId = 100;

  Future<void> init() async {
    if (_ready) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      requestCriticalPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );
    final a = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await a?.requestNotificationsPermission();
    _ready = true;
  }

  Future<void> show(DetectionEvent e) async {
    if (!_ready) await init();
    final critical = isCritical(e.kind);
    final android = AndroidNotificationDetails(
      critical ? 'critical' : 'events',
      critical ? 'هشدار آتش و دود' : 'رویدادهای دوربین',
      channelDescription: critical
          ? 'هشدارهای فوری آتش‌سوزی و دود'
          : 'حرکت و وضعیت اتصال دوربین‌ها',
      importance: critical ? Importance.max : Importance.high,
      priority: critical ? Priority.max : Priority.high,
      category: critical
          ? AndroidNotificationCategory.alarm
          : AndroidNotificationCategory.message,
      fullScreenIntent: critical,
      audioAttributesUsage: critical
          ? AudioAttributesUsage.alarm
          : AudioAttributesUsage.notification,
      playSound: true,
      enableVibration: true,
      styleInformation: e.snapshotPath != null
          ? BigPictureStyleInformation(
              FilePathAndroidBitmap(e.snapshotPath!),
              hideExpandedLargeIcon: true,
            )
          : null,
    );
    final ios = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      interruptionLevel: critical
          ? InterruptionLevel.timeSensitive
          : InterruptionLevel.active,
    );
    final title = switch (e.kind) {
      EventKind.fire => '🔥 هشدار آتش‌سوزی',
      EventKind.smoke => '⚠️ هشدار دود',
      EventKind.motion => 'حرکت تشخیص داده شد',
      EventKind.offline => 'ارتباط دوربین قطع شد',
      EventKind.online => 'ارتباط دوربین برقرار شد',
    };
    await _plugin.show(
      _nextId++,
      title,
      e.cameraName,
      NotificationDetails(android: android, iOS: ios),
    );
  }
}
