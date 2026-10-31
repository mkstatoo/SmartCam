import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/app_settings.dart';
import '../models/camera_config.dart';
import '../models/detection_event.dart';
import '../models/license.dart';
import 'account_manager.dart';
import 'alarm_service.dart';
import 'background_service.dart';
import 'camera_monitor.dart';
import 'notification_service.dart';
import 'storage.dart';

/// مرکز فرماندهی برنامه: دوربین‌ها، رویدادها، آلارم و اعلان‌ها.
class MonitorManager extends ChangeNotifier {
  late final Storage _storage;
  late final AlarmService alarm;
  final NotificationService notifications = NotificationService();

  AppSettings settings = AppSettings();
  final List<CameraConfig> cameras = [];
  final Map<String, CameraMonitor> monitors = {};
  final List<DetectionEvent> events = [];

  /// رویداد بحرانی فعالی که صفحهٔ هشدار تمام‌صفحه برایش باز است.
  final ValueNotifier<DetectionEvent?> activeAlarm = ValueNotifier(null);

  bool _monitoring = false;
  bool get monitoring => _monitoring;

  Limits _appliedLimits = Limits.free;

  /// دوربین‌هایی که مجوز فعلی اجازهٔ پایششان را می‌دهد (به ترتیب فهرست).
  List<CameraConfig> _allowed() =>
      cameras.where((c) => c.enabled).take(account.limits.maxCameras).toList();

  bool get canAddCamera => cameras.length < account.limits.maxCameras;

  bool canEnable(CameraConfig c) =>
      c.enabled ||
      cameras.where((x) => x.enabled).length < account.limits.maxCameras;

  Future<void> init() async {
    _storage = await Storage.open();
    settings = _storage.loadSettings();
    alarm = AlarmService(settings);
    cameras
      ..clear()
      ..addAll(await _storage.loadCameras());
    events
      ..clear()
      ..addAll(_storage.loadEvents());
    for (final c in cameras) {
      _ensureMonitor(c);
    }
    await notifications.init();
    account.cameraCount = () => cameras.length;
    _appliedLimits = account.limits;
    account.addListener(_onAccountChanged);
    notifyListeners();
    if (_storage.monitoringWanted) await startMonitoring();
  }

  CameraMonitor _ensureMonitor(CameraConfig c) => monitors.putIfAbsent(
    c.id,
    () => CameraMonitor(
      c,
      onEvent: _onEvent,
      saveSnapshot: (id, jpeg) => _storage.writeSnapshot(id, jpeg),
    ),
  );

  // ---------------- شروع/توقف ----------------

  Future<void> startMonitoring() async {
    _monitoring = true;
    await _storage.setMonitoringWanted(true);
    final lim = account.limits;
    await BackgroundService.start(
      // بدون سرویس پیش‌زمینه (رایگان) صفحه باید روشن بماند تا پایش قطع نشود
      keepScreenOn: settings.keepScreenOn || !lim.background,
      foreground: lim.background,
    );
    for (final c in _allowed()) {
      await _ensureMonitor(c).start();
    }
    notifyListeners();
  }

  void _onAccountChanged() {
    final lim = account.limits;
    if (lim == _appliedLimits) return;
    final old = _appliedLimits;
    _appliedLimits = lim;
    unawaited(_applyLimits(old));
  }

  /// مجوز عوض شد (خرید، انقضا، لغو): پایش را با محدودیت‌های جدید دوباره می‌چینیم.
  Future<void> _applyLimits(Limits old) async {
    if (_monitoring) {
      final allowed = _allowed().map((c) => c.id).toSet();
      for (final c in cameras) {
        final m = monitors[c.id];
        if (m == null) continue;
        if (c.enabled && allowed.contains(c.id)) {
          if (m.running) {
            await m.restart(c);
          } else {
            await m.start();
          }
        } else {
          await m.stop();
        }
      }
      if (old.background != _appliedLimits.background) {
        await BackgroundService.stop();
        await BackgroundService.start(
          keepScreenOn: settings.keepScreenOn || !_appliedLimits.background,
          foreground: _appliedLimits.background,
        );
      }
    }
    _trimEvents();
    await _storage.saveEvents(events);
    notifyListeners();
  }

  Future<void> stopMonitoring() async {
    _monitoring = false;
    await _storage.setMonitoringWanted(false);
    for (final m in monitors.values) {
      await m.stop();
    }
    await alarm.stopSiren();
    await BackgroundService.stop();
    notifyListeners();
  }

  // ---------------- دوربین‌ها ----------------

  Future<void> saveCamera(CameraConfig c) async {
    final i = cameras.indexWhere((e) => e.id == c.id);
    if (i >= 0) {
      cameras[i] = c;
      await monitors[c.id]?.restart(c);
    } else {
      cameras.add(c);
      final m = _ensureMonitor(c);
      if (_monitoring && c.enabled && _allowed().any((x) => x.id == c.id)) {
        await m.start();
      }
    }
    await _storage.saveCameras(cameras);
    notifyListeners();
  }

  Future<void> deleteCamera(String id) async {
    final m = monitors.remove(id);
    await m?.stop();
    m?.dispose();
    cameras.removeWhere((c) => c.id == id);
    await _storage.deleteCredentials(id);
    await _storage.saveCameras(cameras);
    notifyListeners();
  }

  Future<void> setCameraEnabled(CameraConfig c, bool v) async {
    c.enabled = v;
    final m = _ensureMonitor(c);
    if (!v) {
      await m.stop();
    } else if (_monitoring) {
      m.config = c;
      await m.start();
    }
    await _storage.saveCameras(cameras);
    notifyListeners();
  }

  // ---------------- رویدادها ----------------

  void _onEvent(DetectionEvent e) {
    events.insert(0, e);
    account.countEvent(e.kind);
    _trimEvents();
    _storage.saveEvents(events);

    notifications.show(e);

    if (isCritical(e.kind)) {
      alarm.startSiren();
      activeAlarm.value = e;
    } else if (e.kind == EventKind.motion) {
      alarm.motionAlert();
    }
    notifyListeners();
  }

  void _trimEvents() {
    final cap = math.min(settings.maxStoredEvents, account.limits.maxEvents);
    while (events.length > cap) {
      final old = events.removeLast();
      _storage.deleteSnapshot(old.snapshotPath);
    }
  }

  Future<void> acknowledge(DetectionEvent e) async {
    e.acknowledged = true;
    if (activeAlarm.value?.id == e.id) activeAlarm.value = null;
    // اگر هشدار بحرانی بی‌پاسخ دیگری نمانده، آژیر خاموش می‌شود.
    final pending = events.any((x) => isCritical(x.kind) && !x.acknowledged);
    if (!pending) await alarm.stopSiren();
    await _storage.saveEvents(events);
    notifyListeners();
  }

  Future<void> silenceAll() async {
    for (final e in events) {
      if (isCritical(e.kind)) e.acknowledged = true;
    }
    activeAlarm.value = null;
    await alarm.stopSiren();
    await _storage.saveEvents(events);
    notifyListeners();
  }

  Future<void> clearEvents() async {
    for (final e in events) {
      await _storage.deleteSnapshot(e.snapshotPath);
    }
    events.clear();
    await _storage.saveEvents(events);
    notifyListeners();
  }

  // ---------------- تنظیمات ----------------

  Future<void> saveSettings() async {
    alarm.settings = settings;
    await _storage.saveSettings(settings);
    notifyListeners();
  }
}

/// نمونهٔ سراسری (ساده و کافی برای این برنامه).
final MonitorManager manager = MonitorManager();
