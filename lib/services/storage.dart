import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';
import '../models/camera_config.dart';
import '../models/detection_event.dart';

/// ذخیره‌سازی محلی: پیکربندی دوربین‌ها و رویدادها در SharedPreferences،
/// نام کاربری/رمز دوربین‌ها در حافظهٔ امن سیستم‌عامل، عکس رویدادها در پوشه.
class Storage {
  Storage._(this._prefs, this.snapshotDir);

  final SharedPreferences _prefs;
  final Directory snapshotDir;
  final _secure = const FlutterSecureStorage();

  static Future<Storage> open() async {
    final prefs = await SharedPreferences.getInstance();
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'snapshots'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return Storage._(prefs, dir);
  }

  // ---------- دوربین‌ها ----------
  Future<List<CameraConfig>> loadCameras() async {
    final s = _prefs.getString('cameras');
    if (s == null || s.isEmpty) return [];
    final list = CameraConfig.decodeList(s);
    for (final c in list) {
      final raw = await _secure.read(key: 'cred_${c.id}');
      if (raw != null) {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        c.username = j['u'] as String? ?? '';
        c.password = j['p'] as String? ?? '';
      }
    }
    return list;
  }

  Future<void> saveCameras(List<CameraConfig> list) async {
    await _prefs.setString('cameras', CameraConfig.encodeList(list));
    for (final c in list) {
      await _secure.write(
        key: 'cred_${c.id}',
        value: jsonEncode({'u': c.username, 'p': c.password}),
      );
    }
  }

  Future<void> deleteCredentials(String id) => _secure.delete(key: 'cred_$id');

  // ---------- تنظیمات ----------
  AppSettings loadSettings() {
    final s = _prefs.getString('settings');
    if (s == null) return AppSettings();
    try {
      return AppSettings.fromJson(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      return AppSettings();
    }
  }

  Future<void> saveSettings(AppSettings s) =>
      _prefs.setString('settings', jsonEncode(s.toJson()));

  bool get monitoringWanted => _prefs.getBool('monitoring') ?? false;
  Future<void> setMonitoringWanted(bool v) => _prefs.setBool('monitoring', v);

  // ---------- رویدادها ----------
  List<DetectionEvent> loadEvents() {
    final s = _prefs.getString('events');
    if (s == null) return [];
    try {
      return (jsonDecode(s) as List)
          .map(
            (e) => DetectionEvent.fromJson((e as Map).cast<String, dynamic>()),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveEvents(List<DetectionEvent> events) => _prefs.setString(
    'events',
    jsonEncode(events.map((e) => e.toJson()).toList()),
  );

  Future<String> writeSnapshot(String id, List<int> jpeg) async {
    final f = File(p.join(snapshotDir.path, '$id.jpg'));
    await f.writeAsBytes(jpeg, flush: true);
    return f.path;
  }

  Future<void> deleteSnapshot(String? path) async {
    if (path == null) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
