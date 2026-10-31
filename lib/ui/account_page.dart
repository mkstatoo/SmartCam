import 'package:flutter/material.dart';

import '../config.dart';
import '../models/license.dart';
import '../services/account_manager.dart';
import '../services/api_client.dart';
import '../services/billing.dart';
import 'paywall.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  List<DeviceInfoRow> _devices = const [];
  int _currentDevice = -1;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await account.fetchMe();
      if (!mounted) return;
      setState(() {
        _devices = r.devices;
        _currentDevice = r.currentDeviceId;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<String?> _askPassword(String title, {String hint = 'رمز عبور'}) async {
    final c = TextEditingController();
    final r = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          obscureText: true,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(labelText: hint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('تأیید')),
        ],
      ),
    );
    c.dispose();
    return (r == null || r.isEmpty) ? null : r;
  }

  Future<void> _changePassword() async {
    final oldPw = await _askPassword('رمز فعلی', hint: 'رمز فعلی');
    if (oldPw == null || !mounted) return;
    final newPw = await _askPassword('رمز جدید (حداقل ۸ نویسه)', hint: 'رمز جدید');
    if (newPw == null) return;
    if (newPw.length < 8) return _snack('رمز جدید حداقل ۸ نویسه باشد');
    try {
      await account.changePassword(oldPw, newPw);
      _snack('رمز عوض شد؛ نشست دستگاه‌های دیگر بسته شد');
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف حساب'),
        content: const Text(
          'حساب شما و اطلاعات آن از سرور حذف می‌شود و نسخهٔ پرو از این حساب برداشته می‌شود '
          '(با همان خرید فروشگاه می‌توانید در حساب جدید «بازیابی خرید» بزنید). '
          'دوربین‌ها و رویدادهای روی همین گوشی دست‌نخورده می‌مانند.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ادامه'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final pw = await _askPassword('برای تأیید، رمز را وارد کنید');
    if (pw == null) return;
    try {
      await account.deleteAccount(pw);
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _logout() async {
    await account.logout();
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _restore() async {
    final r = await billing.restore();
    _snack(r.ok ? 'خرید بازیابی شد' : (r.message ?? 'انجام نشد'));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: account,
      builder: (context, _) {
        final lic = account.license;
        final lim = account.limits;
        final pro = account.isPro;
        final u = account.user;
        return Scaffold(
          appBar: AppBar(title: const Text('حساب کاربری')),
          body: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(
                      u == null ? '—' : (u.name.isEmpty ? u.identifier : u.name),
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.right,
                    ),
                    subtitle: Text(u?.identifier ?? '', textDirection: TextDirection.ltr, textAlign: TextAlign.right),
                    trailing: Chip(
                      avatar: Icon(pro ? Icons.workspace_premium : Icons.lock_outline, size: 18),
                      label: Text(pro ? 'پرو' : 'رایگان'),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pro ? 'نسخهٔ پرو فعال است' : 'محدودیت‌های نسخهٔ رایگان',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        if (pro) ...[
                          Text(_proUntilText(lic)),
                        ] else ...[
                          _row('تعداد دوربین', '${lim.maxCameras}'),
                          _row('آتش و دود', 'قفل'),
                          _row('ناحیهٔ پایش', 'قفل'),
                          _row('پایش در پس‌زمینه', 'قفل'),
                          _row('تاریخچهٔ رویداد', '${lim.maxEvents}'),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: () => showPaywall(context),
                              icon: const Icon(Icons.workspace_premium),
                              label: const Text('ارتقا به پرو'),
                            ),
                          ),
                        ],
                        if (lic != null && lic.isPro && !pro)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                              'مدت زیادی با سرور تماس نگرفته‌ایم؛ اینترنت را وصل کنید تا پرو دوباره فعال شود.',
                              style: TextStyle(color: Colors.amberAccent, fontSize: 12),
                            ),
                          ),
                        if (AppConfig.canBuy)
                          TextButton(onPressed: _restore, child: const Text('بازیابی خرید قبلی')),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('دستگاه‌های حساب', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                        const SizedBox(height: 8),
                        if (_loading)
                          const LinearProgressIndicator()
                        else if (_error != null)
                          Text(_error!, style: const TextStyle(color: Colors.redAccent))
                        else
                          for (final d in _devices)
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.smartphone),
                              title: Text(
                                d.model.isEmpty ? 'دستگاه' : d.model,
                                textDirection: TextDirection.ltr,
                                textAlign: TextAlign.right,
                              ),
                              subtitle: Text(d.id == _currentDevice ? 'همین گوشی' : 'نسخه ${d.appVersion}'),
                              trailing: d.id == _currentDevice
                                  ? null
                                  : IconButton(
                                      tooltip: 'خروج این دستگاه',
                                      icon: const Icon(Icons.logout),
                                      onPressed: () async {
                                        try {
                                          await account.removeDevice(d.id);
                                          await _load();
                                        } on ApiException catch (e) {
                                          _snack(e.message);
                                        }
                                      },
                                    ),
                            ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(leading: const Icon(Icons.password), title: const Text('تغییر رمز'), onTap: _changePassword),
                ListTile(leading: const Icon(Icons.logout), title: const Text('خروج از حساب'), onTap: _logout),
                ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.redAccent),
                  title: const Text('حذف حساب', style: TextStyle(color: Colors.redAccent)),
                  onTap: _delete,
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    'نسخه ${AppConfig.appVersion}'
                    '${AppConfig.storeLabel.isEmpty ? '' : ' • ${AppConfig.storeLabel}'}',
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _proUntilText(License? l) {
    if (l == null || l.proUntil == null) return 'اعتبار: دائمی';
    final left = l.proUntil! - DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return 'اعتبار: ${(left / 86400).ceil().clamp(0, 99999)} روز دیگر';
  }

  Widget _row(String a, String b) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(child: Text(a, style: const TextStyle(color: Colors.white70))),
        Text(b),
      ],
    ),
  );
}
