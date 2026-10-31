import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'models/detection_event.dart';
import 'services/account_manager.dart';
import 'services/monitor_manager.dart';
import 'ui/alarm_overlay.dart';
import 'ui/auth_page.dart';
import 'ui/events_page.dart';
import 'ui/home_page.dart';
import 'ui/settings_page.dart';

class DetectiveCameraApp extends StatelessWidget {
  const DetectiveCameraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'کارآگاه دوربین',
      debugShowCheckedModeBanner: false,
      locale: const Locale('fa', 'IR'),
      supportedLocales: const [Locale('fa', 'IR'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFFE8590C),
        scaffoldBackgroundColor: const Color(0xFF101114),
      ),
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: Stack(
          children: [
            child ?? const SizedBox.shrink(),
            // صفحهٔ هشدار تمام‌صفحه روی همهٔ صفحه‌ها
            ValueListenableBuilder<DetectionEvent?>(
              valueListenable: manager.activeAlarm,
              builder: (_, e, __) =>
                  e == null ? const SizedBox.shrink() : AlarmOverlay(event: e),
            ),
          ],
        ),
      ),
      home: const _Gate(),
    );
  }
}

/// دروازهٔ برنامه: تا وقتی وارد حساب نشده‌ایم صفحهٔ ورود، بعد صفحهٔ اصلی.
class _Gate extends StatefulWidget {
  const _Gate();

  @override
  State<_Gate> createState() => _GateState();
}

class _GateState extends State<_Gate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // با هر بازگشت به برنامه، مجوز تازه می‌شود (حداکثر هر ۱۰ دقیقه یک‌بار)
    if (state == AppLifecycleState.resumed) account.refresh();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: account,
    builder: (_, __) {
      if (!account.ready) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return account.needsLogin ? const AuthPage() : const _Shell();
    },
  );
}

class _Shell extends StatefulWidget {
  const _Shell();

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        final unack = manager.events.where((e) => !e.acknowledged).length;
        return Scaffold(
          body: IndexedStack(
            index: _tab,
            children: const [HomePage(), EventsPage(), SettingsPage()],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.videocam_outlined),
                selectedIcon: Icon(Icons.videocam),
                label: 'دوربین‌ها',
              ),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: unack > 0,
                  label: Text('$unack'),
                  child: const Icon(Icons.notifications_outlined),
                ),
                selectedIcon: const Icon(Icons.notifications),
                label: 'رویدادها',
              ),
              const NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: 'تنظیمات',
              ),
            ],
          ),
        );
      },
    );
  }
}
