import 'package:flutter/material.dart';

import '../core/frame.dart';
import '../models/camera_config.dart';
import '../services/account_manager.dart';
import '../services/monitor_manager.dart';
import '../services/onvif_client.dart';
import '../sources/source_factory.dart';
import 'frame_view.dart';
import 'paywall.dart';
import 'zone_editor_page.dart';

class CameraEditPage extends StatefulWidget {
  const CameraEditPage({super.key, this.existing});
  final CameraConfig? existing;

  @override
  State<CameraEditPage> createState() => _CameraEditPageState();
}

class _CameraEditPageState extends State<CameraEditPage> {
  late final CameraConfig _c;
  late final TextEditingController _name, _url, _user, _pass;
  final _form = GlobalKey<FormState>();
  final ValueNotifier<RgbFrame?> _preview = ValueNotifier(null);
  bool _testing = false;
  String? _testMsg;
  bool _testOk = false;
  bool _showPass = false;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    _c =
        widget.existing?.copy() ??
        CameraConfig(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          name: 'دوربین ${manager.cameras.length + 1}',
          type: SourceType.stream,
        );
    _name = TextEditingController(text: _c.name);
    _url = TextEditingController(text: _c.url);
    _user = TextEditingController(text: _c.username);
    _pass = TextEditingController(text: _c.password);
    _preview.value = manager.monitors[_c.id]?.lastFrame.value;
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _user.dispose();
    _pass.dispose();
    _preview.dispose();
    super.dispose();
  }

  void _syncFromFields() {
    _c
      ..name = _name.text.trim()
      ..url = _url.text.trim()
      ..username = _user.text.trim()
      ..password = _pass.text;
  }

  String get _hint => switch (_c.type) {
    SourceType.stream => 'rtsp://192.168.1.10:554/stream1',
    SourceType.mjpeg => 'http://192.168.1.20:8080/video',
    SourceType.snapshot => 'http://192.168.1.20:8080/shot.jpg',
    SourceType.phone => '',
  };

  String? _validateUrl(String? v) {
    if (_c.type == SourceType.phone) return null;
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'آدرس را وارد کنید';
    final u = Uri.tryParse(s);
    if (u == null || !u.hasScheme || u.host.isEmpty) return 'آدرس معتبر نیست';
    if (_c.type == SourceType.stream) {
      const ok = ['rtsp', 'rtsps', 'rtmp', 'http', 'https', 'udp', 'rtp'];
      if (!ok.contains(u.scheme)) return 'پروتکل پشتیبانی نمی‌شود';
    } else if (u.scheme != 'http' && u.scheme != 'https') {
      return 'آدرس باید با http شروع شود';
    }
    return null;
  }

  Future<void> _test() async {
    if (!_form.currentState!.validate()) return;
    _syncFromFields();
    setState(() {
      _testing = true;
      _testMsg = null;
    });
    final r = await testSource(_c);
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testOk = r.ok;
      _testMsg = r.ok
          ? 'اتصال برقرار شد (${r.frame!.width}×${r.frame!.height})'
          : 'اتصال ناموفق: ${r.error}';
      if (r.ok) _preview.value = r.frame;
    });
  }

  Future<void> _discover() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('در حال جست‌وجوی دوربین‌های ONVIF در شبکه…'),
        duration: Duration(seconds: 4),
      ),
    );
    List<OnvifDevice> devices;
    try {
      devices = await OnvifClient.discover();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('جست‌وجو ناموفق بود: $e')));
      return;
    }
    if (!mounted) return;
    if (devices.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'دوربین ONVIF پیدا نشد. گوشی و دوربین باید روی یک شبکه باشند.',
          ),
        ),
      );
      return;
    }
    final dev = await showModalBottomSheet<OnvifDevice>(
      context: context,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('دوربین‌های پیدا شده')),
            for (final d in devices)
              ListTile(
                leading: const Icon(Icons.videocam),
                title: Text(d.name ?? d.host),
                subtitle: Text(d.host, textDirection: TextDirection.ltr),
                onTap: () => Navigator.of(context).pop(d),
              ),
          ],
        ),
      ),
    );
    if (dev == null || !mounted) return;

    // نام کاربری و رمز (برای ONVIF معمولاً لازم است)
    final u = TextEditingController(text: _user.text);
    final p = TextEditingController(text: _pass.text);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('ورود به ${dev.name ?? dev.host}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: u,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(labelText: 'نام کاربری'),
            ),
            TextField(
              controller: p,
              obscureText: true,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(labelText: 'رمز عبور'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('دریافت آدرس جریان'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final rtsp = await OnvifClient.fetchStreamUri(
        deviceServiceUrl: dev.xaddr,
        username: u.text.trim(),
        password: p.text,
      );
      if (!mounted) return;
      setState(() {
        _user.text = u.text.trim();
        _pass.text = p.text;
        _url.text = rtsp;
        if (_name.text.startsWith('دوربین ') && dev.name != null) {
          _name.text = dev.name!;
        }
      });
      messenger.showSnackBar(
        const SnackBar(content: Text('آدرس جریان از دوربین دریافت شد')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  bool _requirePro(bool allowed, String what) {
    if (allowed) return true;
    showPaywall(context, reason: '$what در نسخهٔ پرو فعال است.');
    return false;
  }

  Future<void> _editZone() async {
    if (!_requirePro(account.limits.zones, 'تعیین ناحیهٔ پایش')) return;
    final z = await Navigator.of(context).push<dynamic>(
      MaterialPageRoute(
        builder: (_) => ZoneEditorPage(initial: _c.zone, frame: _preview.value),
      ),
    );
    if (z != null) setState(() => _c.zone = z);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_isNew && !manager.canAddCamera) {
      showPaywall(
        context,
        reason: 'نسخهٔ رایگان حداکثر ${account.limits.maxCameras} دوربین دارد.',
      );
      return;
    }
    _syncFromFields();
    await manager.saveCamera(_c);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف دوربین'),
        content: Text('«${_c.name}» حذف شود؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await manager.deleteCamera(_c.id);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final needsUrl = _c.type != SourceType.phone;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'دوربین جدید' : 'ویرایش دوربین'),
        actions: [
          if (!_isNew)
            IconButton(
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
            ),
          TextButton(onPressed: _save, child: const Text('ذخیره')),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: FrameView(source: _preview, zone: _c.zone),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'نام دوربین',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'نام را وارد کنید' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<SourceType>(
              value: _c.type,
              decoration: const InputDecoration(
                labelText: 'نوع منبع تصویر',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final t in SourceType.values)
                  DropdownMenuItem(value: t, child: Text(sourceTypeLabel(t))),
              ],
              onChanged: (t) => setState(() {
                _c.type = t!;
                _testMsg = null;
              }),
            ),
            if (needsUrl) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _url,
                textDirection: TextDirection.ltr,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: 'آدرس',
                  hintText: _hint,
                  hintTextDirection: TextDirection.ltr,
                  border: const OutlineInputBorder(),
                ),
                validator: _validateUrl,
              ),
              if (_c.type == SourceType.stream)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: _discover,
                    icon: const Icon(Icons.radar),
                    label: const Text('یافتن خودکار دوربین (ONVIF)'),
                  ),
                ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _user,
                      textDirection: TextDirection.ltr,
                      decoration: const InputDecoration(
                        labelText: 'نام کاربری',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _pass,
                      obscureText: !_showPass,
                      textDirection: TextDirection.ltr,
                      decoration: InputDecoration(
                        labelText: 'رمز عبور',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _showPass ? Icons.visibility_off : Icons.visibility,
                          ),
                          onPressed: () =>
                              setState(() => _showPass = !_showPass),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 12),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('دوربین پشت')),
                  ButtonSegment(value: 1, label: Text('دوربین جلو')),
                ],
                selected: {_c.phoneCameraIndex.clamp(0, 1)},
                onSelectionChanged: (s) =>
                    setState(() => _c.phoneCameraIndex = s.first),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: _testing ? null : _test,
                  icon: _testing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering),
                  label: const Text('آزمایش اتصال'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _testMsg ?? '',
                    style: TextStyle(
                      fontSize: 12,
                      color: _testOk ? Colors.greenAccent : Colors.redAccent,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 32),
            _sectionTitle('نرخ تحلیل'),
            _slider(
              '${_c.fps.toStringAsFixed(1)} فریم در ثانیه',
              _c.fps,
              0.5,
              5,
              (v) => setState(() => _c.fps = (v * 2).round() / 2),
              divisions: 9,
            ),
            const Text(
              'نرخ کمتر = مصرف باتری/CPU کمتر. برای آتش‌سوزی حداقل ۲ فریم در ثانیه توصیه می‌شود.',
              style: TextStyle(fontSize: 12, color: Colors.white54),
            ),
            const Divider(height: 32),
            _sectionTitle('تشخیص‌ها'),
            SwitchListTile(
              value: _c.motionEnabled,
              onChanged: (v) => setState(() => _c.motionEnabled = v),
              title: const Text('حرکت'),
              secondary: const Icon(Icons.directions_run),
            ),
            if (_c.motionEnabled)
              _slider(
                'حساسیت حرکت',
                _c.motionSensitivity,
                0,
                1,
                (v) => setState(() => _c.motionSensitivity = v),
              ),
            SwitchListTile(
              value: _c.fireEnabled && account.limits.fireSmoke,
              onChanged: (v) {
                if (v && !_requirePro(account.limits.fireSmoke, 'تشخیص آتش')) {
                  return;
                }
                setState(() => _c.fireEnabled = v);
              },
              title: const Text('آتش'),
              subtitle: Text(
                account.limits.fireSmoke
                    ? 'با رنگ شعله و سوسوزدن'
                    : 'نیازمند نسخهٔ پرو 🔒',
              ),
              secondary: const Icon(Icons.local_fire_department),
            ),
            if (_c.fireEnabled && account.limits.fireSmoke)
              _slider(
                'حساسیت آتش',
                _c.fireSensitivity,
                0,
                1,
                (v) => setState(() => _c.fireSensitivity = v),
              ),
            SwitchListTile(
              value: _c.smokeEnabled && account.limits.fireSmoke,
              onChanged: (v) {
                if (v && !_requirePro(account.limits.fireSmoke, 'تشخیص دود')) {
                  return;
                }
                setState(() => _c.smokeEnabled = v);
              },
              title: const Text('دود (آزمایشی)'),
              subtitle: Text(
                account.limits.fireSmoke
                    ? 'خطای کاذب بیشتری دارد'
                    : 'نیازمند نسخهٔ پرو 🔒',
              ),
              secondary: const Icon(Icons.cloud),
            ),
            if (_c.smokeEnabled && account.limits.fireSmoke)
              _slider(
                'حساسیت دود',
                _c.smokeSensitivity,
                0,
                1,
                (v) => setState(() => _c.smokeSensitivity = v),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _editZone,
              icon: const Icon(Icons.crop_free),
              label: Text(
                !account.limits.zones
                    ? 'تعیین ناحیهٔ پایش (پرو 🔒)'
                    : _c.zone.isFullFrame
                    ? 'تعیین ناحیهٔ پایش (الان: کل تصویر)'
                    : 'ویرایش ناحیهٔ پایش (${_c.zone.include.length} سبز، ${_c.zone.exclude.length} قرمز)',
              ),
            ),
            if (_preview.value == null)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'برای دیدن تصویر هنگام رسم ناحیه، اول «آزمایش اتصال» بزنید.',
                  style: TextStyle(fontSize: 12, color: Colors.white54),
                ),
              ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      t,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
    ),
  );

  Widget _slider(
    String label,
    double v,
    double min,
    double max,
    ValueChanged<double> on, {
    int? divisions,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Row(
      children: [
        SizedBox(
          width: 130,
          child: Text(label, style: const TextStyle(fontSize: 13)),
        ),
        Expanded(
          child: Slider(
            value: v.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: on,
          ),
        ),
      ],
    ),
  );
}
