import 'package:flutter/material.dart';

import '../config.dart';
import '../services/account_manager.dart';
import '../services/api_client.dart';

const String kPrivacySummary =
    'اطلاعاتی که به سرور ما فرستاده می‌شود:\n'
    '• ایمیل یا شمارهٔ موبایل و نامی که وارد می‌کنید\n'
    '• مدل گوشی، نسخهٔ برنامه و فروشگاه نصب\n'
    '• تعداد دوربین‌ها و تعداد رویدادها به تفکیک نوع (حرکت/آتش/دود/قطع) فقط به‌صورت عدد\n'
    '• وضعیت خرید نسخهٔ پرو\n\n'
    'هرگز ارسال نمی‌شود: تصویر و ویدیو، عکس رویدادها، آدرس/نام کاربری/رمز دوربین‌ها.\n'
    'تحلیل تصویر کاملاً روی گوشی شما انجام می‌شود.\n\n'
    'با «حذف حساب» در صفحهٔ حساب کاربری، اطلاعات حساب شما از سرور پاک می‌شود.';

/// صفحهٔ ورود/ثبت‌نام. بعد از موفقیت، [AccountManager] نوتیفای می‌شود و دروازهٔ برنامه خودش عوض می‌شود.
class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _form = GlobalKey<FormState>();
  final _id = TextEditingController();
  final _pw = TextEditingController();
  final _name = TextEditingController();
  bool _register = true;
  bool _accept = false;
  bool _busy = false;
  bool _showPw = false;
  String? _error;

  @override
  void dispose() {
    _id.dispose();
    _pw.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit({int? revokeDeviceId}) async {
    if (!_form.currentState!.validate()) return;
    if (_register && !_accept) {
      setState(() => _error = 'برای ادامه باید سیاست حریم خصوصی را بپذیرید');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_register) {
        await account.register(
          identifier: _id.text.trim(),
          password: _pw.text,
          name: _name.text.trim(),
        );
      } else {
        await account.login(
          identifier: _id.text.trim(),
          password: _pw.text,
          revokeDeviceId: revokeDeviceId,
        );
      }
    } on ApiException catch (e) {
      if (e.code == 'device_limit') {
        await _pickDeviceToRemove(e);
      } else if (mounted) {
        setState(() => _error = e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickDeviceToRemove(ApiException e) async {
    final devices = ((e.body['devices'] as List?) ?? const [])
        .map((d) => (d as Map).cast<String, dynamic>())
        .toList();
    final id = await showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('سقف دستگاه‌ها پر است'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('برای ورود با این گوشی، یکی از دستگاه‌های قبلی را از حساب خارج کنید:'),
            const SizedBox(height: 8),
            for (final d in devices)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.smartphone),
                title: Text(
                  (d['model'] as String?)?.isNotEmpty == true ? d['model'] as String : 'دستگاه',
                  textDirection: TextDirection.ltr,
                ),
                subtitle: Text(_agoFa((d['last_seen'] as num?)?.toInt())),
                onTap: () => Navigator.pop(context, (d['id'] as num).toInt()),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
        ],
      ),
    );
    if (id != null && mounted) await _submit(revokeDeviceId: id);
  }

  void _showPolicy() => showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('حریم خصوصی'),
      content: SingleChildScrollView(
        child: Text(
          kPrivacySummary + (AppConfig.privacyUrl.isEmpty ? '' : '\n\nمتن کامل: ${AppConfig.privacyUrl}'),
          style: const TextStyle(height: 1.8),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('بستن'))],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.shield_moon, size: 64, color: cs.primary),
                    const SizedBox(height: 8),
                    const Text(
                      'کارآگاه دوربین',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'تشخیص حرکت، آتش و دود از دوربین‌های شما',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white60),
                    ),
                    const SizedBox(height: 24),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: true, label: Text('ثبت‌نام')),
                        ButtonSegment(value: false, label: Text('ورود')),
                      ],
                      selected: {_register},
                      onSelectionChanged: (s) => setState(() {
                        _register = s.first;
                        _error = null;
                      }),
                    ),
                    const SizedBox(height: 16),
                    if (_register) ...[
                      TextFormField(
                        controller: _name,
                        decoration: const InputDecoration(
                          labelText: 'نام (اختیاری)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextFormField(
                      controller: _id,
                      textDirection: TextDirection.ltr,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.username],
                      decoration: const InputDecoration(
                        labelText: 'ایمیل یا شمارهٔ موبایل',
                        hintText: '09123456789',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          (v ?? '').trim().isEmpty ? 'ایمیل یا شمارهٔ موبایل را وارد کنید' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _pw,
                      obscureText: !_showPw,
                      textDirection: TextDirection.ltr,
                      autofillHints: [
                        _register ? AutofillHints.newPassword : AutofillHints.password,
                      ],
                      decoration: InputDecoration(
                        labelText: 'رمز عبور',
                        helperText: _register ? 'حداقل ۸ نویسه' : null,
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(_showPw ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _showPw = !_showPw),
                        ),
                      ),
                      validator: (v) {
                        final s = v ?? '';
                        if (s.isEmpty) return 'رمز عبور را وارد کنید';
                        if (_register && s.length < 8) return 'رمز حداقل ۸ نویسه باشد';
                        return null;
                      },
                    ),
                    if (_register)
                      CheckboxListTile(
                        value: _accept,
                        onChanged: (v) => setState(() => _accept = v ?? false),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('سیاست حریم خصوصی را می‌پذیرم', style: TextStyle(fontSize: 13)),
                        subtitle: InkWell(
                          onTap: _showPolicy,
                          child: Text(
                            'چه اطلاعاتی ارسال می‌شود؟',
                            style: TextStyle(color: cs.primary, fontSize: 12),
                          ),
                        ),
                      ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 50,
                      child: FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(_register ? 'ساخت حساب' : 'ورود'),
                      ),
                    ),
                    if (!_register)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text(
                          'رمز را فراموش کرده‌اید؟ از راه تماس درج‌شده در صفحهٔ برنامه در فروشگاه '
                          'به پشتیبانی پیام دهید تا رمز موقت بدهند.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _agoFa(int? epoch) {
  if (epoch == null || epoch == 0) return '—';
  final d = DateTime.now().millisecondsSinceEpoch ~/ 1000 - epoch;
  if (d < 120) return 'همین الان';
  if (d < 3600) return '${d ~/ 60} دقیقه پیش';
  if (d < 86400) return '${d ~/ 3600} ساعت پیش';
  return '${d ~/ 86400} روز پیش';
}
