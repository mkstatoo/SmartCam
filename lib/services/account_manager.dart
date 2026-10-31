import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../models/detection_event.dart';
import '../models/license.dart';
import 'api_client.dart';

int _nowSec() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

/// حساب کاربری، مجوز (رایگان/پرو) و ارسال آمار ناشناس مصرف به سرور.
///
/// اصل طراحی: سرور مرجع است، ولی برنامه بدون اینترنت هم کار می‌کند
/// (مجوز آخرین بار تأییدشده تا [License.graceDays] روز معتبر می‌ماند).
class AccountManager extends ChangeNotifier {
  static const _kToken = 'acc_token';
  static const _kUser = 'acc_user';
  static const _kLicense = 'acc_license';
  static const _kUid = 'acc_device_uid';
  static const _kDelta = 'acc_delta';

  late SharedPreferences _prefs;
  final _secure = const FlutterSecureStorage();
  ApiClient? _api;

  bool ready = false;
  String? _token;
  AccountUser? user;
  License? _license;
  String _uid = '';
  String _model = '';
  Timer? _timer;
  Timer? _saveDelta;
  DateTime _lastRefresh = DateTime.fromMillisecondsSinceEpoch(0);
  final Map<String, int> _delta = {'motion': 0, 'fire': 0, 'smoke': 0, 'offline': 0};

  /// تعداد دوربین‌های ثبت‌شده؛ MonitorManager مقدار می‌دهد.
  int Function() cameraCount = () => 0;

  /// آخرین پیام خطای شبکه برای نمایش در صفحهٔ حساب.
  String? lastError;

  bool get loggedIn => !AppConfig.accountsEnabled || _token != null;
  bool get needsLogin => AppConfig.accountsEnabled && _token == null;
  License? get license => _license;
  String get deviceUid => _uid;

  /// محدودیت مؤثر الان.
  Limits get limits {
    if (!AppConfig.accountsEnabled) return Limits.pro; // ساخت توسعه، بدون سرور
    final l = _license;
    if (l == null || _token == null) return Limits.free;
    return l.effective(_nowSec());
  }

  bool get isPro => limits.fireSmoke && limits.background;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _uid = _prefs.getString(_kUid) ?? '';
    if (_uid.isEmpty) {
      final r = Random.secure();
      _uid = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      await _prefs.setString(_kUid, _uid);
    }
    _model = await _readModel();
    if (AppConfig.accountsEnabled) {
      _api = ApiClient(AppConfig.apiBase);
      _token = await _secure.read(key: _kToken);
      try {
        final u = _prefs.getString(_kUser);
        if (u != null) user = AccountUser.fromJson(jsonDecode(u) as Map<String, dynamic>);
        final l = _prefs.getString(_kLicense);
        if (l != null) _license = License.fromJson(jsonDecode(l) as Map<String, dynamic>);
        final d = _prefs.getString(_kDelta);
        if (d != null) {
          (jsonDecode(d) as Map<String, dynamic>).forEach((k, v) {
            if (_delta.containsKey(k)) _delta[k] = (v as num).toInt();
          });
        }
      } catch (_) {}
    }
    ready = true;
    notifyListeners();
    if (_token != null) unawaited(refresh(force: true));
    _timer = Timer.periodic(const Duration(hours: 4), (_) => refresh());
  }

  Future<String> _readModel() async {
    try {
      final p = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final i = await p.androidInfo;
        return '${i.manufacturer} ${i.model}'.trim();
      }
      if (Platform.isIOS) return (await p.iosInfo).utsname.machine;
    } catch (_) {}
    return Platform.operatingSystem;
  }

  Map<String, dynamic> _device() => {
    'uid': _uid,
    'model': _model.length > 60 ? _model.substring(0, 60) : _model,
    'platform': Platform.operatingSystem,
    'app_version': AppConfig.appVersion,
    'store': AppConfig.store,
  };

  // ---------------- ثبت‌نام / ورود ----------------

  Future<void> register({
    required String identifier,
    required String password,
    String name = '',
  }) async {
    final j = await _api!.post('/api/v1/auth/register', {
      'identifier': identifier,
      'password': password,
      'name': name,
      'accept_terms': true,
      'device': _device(),
    });
    await _applyAuth(j);
  }

  /// اگر سقف دستگاه پر باشد، [ApiException] با code=device_limit و فهرست دستگاه‌ها
  /// در `body['devices']` پرتاب می‌شود.
  Future<void> login({
    required String identifier,
    required String password,
    int? revokeDeviceId,
  }) async {
    final j = await _api!.post('/api/v1/auth/login', {
      'identifier': identifier,
      'password': password,
      'device': _device(),
      if (revokeDeviceId != null) 'revoke_device_id': revokeDeviceId,
    });
    await _applyAuth(j);
  }

  Future<void> _applyAuth(Map<String, dynamic> j) async {
    _token = j['token'] as String;
    await _secure.write(key: _kToken, value: _token);
    user = AccountUser.fromJson((j['user'] as Map).cast<String, dynamic>());
    await _prefs.setString(_kUser, jsonEncode(user!.toJson()));
    await _setLicense((j['license'] as Map).cast<String, dynamic>());
    unawaited(refresh(force: true));
  }

  Future<void> _setLicense(Map<String, dynamic> j) async {
    _license = License.fromServer(j, _nowSec());
    await _prefs.setString(_kLicense, jsonEncode(_license!.toJson()));
    notifyListeners();
  }

  Future<void> logout() async {
    final t = _token;
    if (t != null) {
      try {
        await _api!.post('/api/v1/auth/logout', {}, token: t);
      } catch (_) {}
    }
    await _clearSession();
  }

  Future<void> _clearSession() async {
    _token = null;
    user = null;
    _license = null;
    await _secure.delete(key: _kToken);
    await _prefs.remove(_kUser);
    await _prefs.remove(_kLicense);
    notifyListeners();
  }

  // ---------------- مجوز و آمار ----------------

  void countEvent(EventKind k) {
    final key = switch (k) {
      EventKind.motion => 'motion',
      EventKind.fire => 'fire',
      EventKind.smoke => 'smoke',
      EventKind.offline => 'offline',
      EventKind.online => null,
    };
    if (key == null || !AppConfig.accountsEnabled) return;
    _delta[key] = (_delta[key] ?? 0) + 1;
    _saveDelta?.cancel();
    _saveDelta = Timer(const Duration(seconds: 5), () {
      _prefs.setString(_kDelta, jsonEncode(_delta));
    });
  }

  /// تماس دوره‌ای با سرور: آمار را می‌فرستد و مجوز تازه می‌گیرد.
  Future<void> refresh({bool force = false}) async {
    final t = _token;
    if (t == null || _api == null) return;
    if (!force &&
        DateTime.now().difference(_lastRefresh) < const Duration(minutes: 10)) {
      return;
    }
    _lastRefresh = DateTime.now();
    final sent = Map<String, int>.from(_delta);
    try {
      final j = await _api!.post('/api/v1/heartbeat', {
        'device': _device(),
        'cameras': cameraCount().clamp(0, 1000),
        'events': sent,
      }, token: t);
      for (final k in sent.keys) {
        _delta[k] = ((_delta[k] ?? 0) - sent[k]!).clamp(0, 1 << 30);
      }
      await _prefs.setString(_kDelta, jsonEncode(_delta));
      lastError = null;
      await _setLicense((j['license'] as Map).cast<String, dynamic>());
    } on ApiException catch (e) {
      if (e.unauthorized || e.code == 'banned') {
        lastError = e.message;
        await _clearSession(); // نشست بسته شده یا حساب مسدود است
      } else {
        lastError = e.message; // قطع اینترنت: مجوز ذخیره‌شده معتبر می‌ماند
      }
    }
  }

  /// اطلاعات حساب برای صفحهٔ «حساب کاربری».
  Future<({List<DeviceInfoRow> devices, int currentDeviceId})> fetchMe() async {
    final j = await _call((t) => _api!.get('/api/v1/me', token: t));
    await _setLicense((j['license'] as Map).cast<String, dynamic>());
    return (
      devices: [
        for (final d in (j['devices'] as List)) DeviceInfoRow.fromJson((d as Map).cast<String, dynamic>()),
      ],
      currentDeviceId: (j['current_device_id'] as num).toInt(),
    );
  }

  Future<void> removeDevice(int id) async {
    await _call((t) => _api!.delete('/api/v1/devices/$id', token: t));
  }

  /// ارسال مدرک خرید به سرور برای تأیید و فعال‌سازی پرو.
  Future<void> verifyPurchase({
    required String store,
    required String productId,
    required String purchaseToken,
    String orderId = '',
  }) async {
    final j = await _call(
      (t) => _api!.post('/api/v1/purchase/verify', {
        'store': store,
        'product_id': productId,
        'purchase_token': purchaseToken,
        'order_id': orderId,
      }, token: t),
    );
    await _setLicense((j['license'] as Map).cast<String, dynamic>());
  }

  Future<void> changePassword(String oldPw, String newPw) async {
    await _call(
      (t) => _api!.post('/api/v1/auth/change-password', {
        'old_password': oldPw,
        'new_password': newPw,
      }, token: t),
    );
  }

  Future<void> deleteAccount(String password) async {
    await _call((t) => _api!.delete('/api/v1/account', body: {'password': password}, token: t));
    await _clearSession();
  }

  Future<Map<String, dynamic>> _call(
    Future<Map<String, dynamic>> Function(String token) f,
  ) async {
    final t = _token;
    if (t == null) throw ApiException(401, 'unauthorized', 'ورود لازم است');
    try {
      return await f(t);
    } on ApiException catch (e) {
      if (e.unauthorized || e.code == 'banned') await _clearSession();
      rethrow;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _saveDelta?.cancel();
    super.dispose();
  }
}

final AccountManager account = AccountManager();
