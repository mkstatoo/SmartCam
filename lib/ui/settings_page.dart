import 'package:flutter/material.dart';

import '../config.dart';
import '../models/app_settings.dart';
import '../services/account_manager.dart';
import '../services/background_service.dart';
import '../services/monitor_manager.dart';
import 'account_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  AppSettings get s => manager.settings;

  void _save() {
    manager.saveSettings();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تنظیمات')),
      body: ListView(
        children: [
          if (AppConfig.accountsEnabled)
            ListenableBuilder(
              listenable: account,
              builder: (context, _) => ListTile(
                leading: Icon(
                  account.isPro ? Icons.workspace_premium : Icons.account_circle_outlined,
                ),
                title: const Text('حساب کاربری'),
                subtitle: Text(
                  '${account.isPro ? 'نسخهٔ پرو' : 'نسخهٔ رایگان'}'
                  '${account.user == null ? '' : ' • ${account.user!.identifier}'}',
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.right,
                ),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AccountPage()),
                ),
              ),
            ),
          const _Header('هشدار'),
          ListTile(
            title: const Text('صدای هشدار حرکت'),
            trailing: DropdownButton<MotionSound>(
              value: s.motionSound,
              underline: const SizedBox.shrink(),
              items: [
                for (final m in MotionSound.values)
                  DropdownMenuItem(value: m, child: Text(motionSoundLabel(m))),
              ],
              onChanged: (m) {
                s.motionSound = m!;
                _save();
              },
            ),
          ),
          ListTile(
            title: const Text('بلندی آژیر آتش/دود'),
            subtitle: Slider(
              value: s.sirenVolume,
              onChanged: (v) {
                s.sirenVolume = v;
                _save();
              },
            ),
          ),
          SwitchListTile(
            title: const Text('لرزش'),
            value: s.vibrate,
            onChanged: (v) {
              s.vibrate = v;
              _save();
            },
          ),
          ListTile(
            title: const Text('توقف خودکار آژیر'),
            subtitle: const Text('اگر کسی خاموشش نکرد'),
            trailing: DropdownButton<int>(
              value: s.sirenAutoStopMinutes,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 0, child: Text('هرگز')),
                DropdownMenuItem(value: 2, child: Text('۲ دقیقه')),
                DropdownMenuItem(value: 5, child: Text('۵ دقیقه')),
                DropdownMenuItem(value: 15, child: Text('۱۵ دقیقه')),
              ],
              onChanged: (m) {
                s.sirenAutoStopMinutes = m!;
                _save();
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.volume_up),
            title: const Text('آزمایش آژیر'),
            subtitle: const Text('برای توقف، دکمهٔ زیر را بزنید'),
            trailing: ValueListenableBuilder<bool>(
              valueListenable: manager.alarm.sirenOn,
              builder: (_, on, __) => FilledButton(
                onPressed: () =>
                    on ? manager.alarm.stopSiren() : manager.alarm.startSiren(),
                child: Text(on ? 'توقف' : 'پخش'),
              ),
            ),
          ),
          const _Header('پایداری'),
          SwitchListTile(
            title: const Text('روشن ماندن صفحه هنگام پایش'),
            subtitle: const Text('پایدارترین حالت، مخصوصاً در iOS'),
            value: s.keepScreenOn,
            onChanged: (v) {
              s.keepScreenOn = v;
              _save();
            },
          ),
          ListTile(
            leading: const Icon(Icons.battery_saver),
            title: const Text('تنظیمات باتری (اندروید)'),
            subtitle: const Text(
              'برنامه را در فهرست پیدا کنید و روی «بدون محدودیت» بگذارید؛ '
              'در بعضی گوشی‌ها (شیائومی، سامسونگ، هواوی) بدون این کار سیستم پایش را می‌بندد',
            ),
            onTap: BackgroundService.openBatterySettings,
          ),
          const _Header('درباره'),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'تشخیص آتش و دود در این برنامه بر پایهٔ تحلیل رنگ و حرکت تصویر است و '
              'جایگزین دتکتور دود/حرارت استاندارد نیست. ممکن است هشدار کاذب بدهد یا '
              'یک رویداد واقعی را تشخیص ندهد؛ فقط به‌عنوان یک لایهٔ کمکی استفاده کنید.\n\n'
              'تمام پردازش روی همین گوشی انجام می‌شود و تصویری به اینترنت فرستاده نمی‌شود '
              '(فقط اطلاعات حساب و آمار عددی مصرف به سرور می‌رود). '
              'اگر دوربین‌های دیگران یا مکان عمومی را پایش می‌کنید، قوانین حریم خصوصی را رعایت کنید.',
              style: TextStyle(
                color: Colors.white60,
                height: 1.7,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.t);
  final String t;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Text(
      t,
      style: TextStyle(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
