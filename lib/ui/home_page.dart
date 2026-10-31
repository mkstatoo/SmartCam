import 'package:flutter/material.dart';

import '../config.dart';
import '../models/camera_config.dart';
import '../services/account_manager.dart';
import '../services/camera_monitor.dart';
import '../services/monitor_manager.dart';
import 'camera_edit_page.dart';
import 'frame_view.dart';
import 'paywall.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        final cams = manager.cameras;
        return Scaffold(
          appBar: AppBar(
            title: const Text('کارآگاه دوربین'),
            actions: [
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 12),
                child: FilterChip(
                  avatar: Icon(
                    manager.monitoring ? Icons.shield : Icons.shield_outlined,
                    color: manager.monitoring ? Colors.greenAccent : null,
                  ),
                  label: Text(manager.monitoring ? 'پایش روشن' : 'پایش خاموش'),
                  selected: manager.monitoring,
                  onSelected: (v) =>
                      v ? manager.startMonitoring() : manager.stopMonitoring(),
                ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () {
              if (!manager.canAddCamera) {
                showPaywall(
                  context,
                  reason:
                      'نسخهٔ رایگان حداکثر ${account.limits.maxCameras} دوربین دارد.',
                );
                return;
              }
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const CameraEditPage()));
            },
            icon: const Icon(Icons.add),
            label: const Text('افزودن دوربین'),
          ),
          body: Column(
            children: [
              ListenableBuilder(
                listenable: account,
                builder: (_, __) => const _PlanBanner(),
              ),
              Expanded(
                child: cams.isEmpty
                    ? const _Empty()
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                        itemCount: cams.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (_, i) => CameraTile(config: cams[i]),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// نوار کوچک نسخهٔ رایگان؛ در نسخهٔ پرو دیده نمی‌شود.
class _PlanBanner extends StatelessWidget {
  const _PlanBanner();

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.accountsEnabled || account.isPro) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Card(
        color: const Color(0xFF2B2113),
        child: ListTile(
          dense: true,
          leading: const Icon(Icons.workspace_premium, color: Colors.orangeAccent),
          title: const Text('نسخهٔ رایگان', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: const Text(
            'فقط حرکت، ۲ دوربین، پایش تا وقتی برنامه باز است. آتش و دود با نسخهٔ پرو.',
            style: TextStyle(fontSize: 12),
          ),
          trailing: FilledButton.tonal(
            onPressed: () => showPaywall(context),
            child: const Text('پرو'),
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.videocam_off_outlined, size: 72, color: Colors.white24),
          SizedBox(height: 12),
          Text(
            'هنوز دوربینی اضافه نکرده‌اید',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 6),
          Text(
            'دوربین IP (RTSP/ONVIF/MJPEG)، یک گوشی قدیمی یا دوربین همین گوشی را اضافه کنید، '
            'سپس «پایش» را روشن کنید.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white60),
          ),
        ],
      ),
    ),
  );
}

class CameraTile extends StatelessWidget {
  const CameraTile({super.key, required this.config});
  final CameraConfig config;

  @override
  Widget build(BuildContext context) {
    final mon = manager.monitors[config.id];
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => CameraEditPage(existing: config)),
        ),
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (mon != null && config.enabled)
                    FrameView(source: mon.lastFrame, fit: BoxFit.cover)
                  else
                    const ColoredBox(
                      color: Colors.black,
                      child: Center(
                        child: Icon(
                          Icons.pause_circle_outline,
                          size: 48,
                          color: Colors.white24,
                        ),
                      ),
                    ),
                  if (mon != null)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: ValueListenableBuilder<MonitorState>(
                        valueListenable: mon.state,
                        builder: (_, s, __) => _StatusChip(state: s, mon: mon),
                      ),
                    ),
                  if (mon != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: ValueListenableBuilder<double>(
                        valueListenable: mon.motionLevel,
                        builder: (_, v, __) => LinearProgressIndicator(
                          value: v,
                          minHeight: 3,
                          backgroundColor: Colors.transparent,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          config.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Wrap(
                          spacing: 8,
                          children: [
                            _Badge(Icons.directions_run, config.motionEnabled),
                            _Badge(
                              Icons.local_fire_department,
                              config.fireEnabled && account.limits.fireSmoke,
                            ),
                            _Badge(
                              Icons.cloud,
                              config.smokeEnabled && account.limits.fireSmoke,
                            ),
                            Text(
                              sourceTypeLabel(config.type),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.white54,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: config.enabled,
                    onChanged: (v) {
                      if (v && !manager.canEnable(config)) {
                        showPaywall(
                          context,
                          reason:
                              'نسخهٔ رایگان حداکثر ${account.limits.maxCameras} دوربین فعال دارد.',
                        );
                        return;
                      }
                      manager.setCameraEnabled(config, v);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.icon, this.on);
  final IconData icon;
  final bool on;
  @override
  Widget build(BuildContext context) =>
      Icon(icon, size: 16, color: on ? Colors.orangeAccent : Colors.white24);
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.state, required this.mon});
  final MonitorState state;
  final CameraMonitor mon;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      MonitorState.live => ('زنده', Colors.green),
      MonitorState.connecting => ('در حال اتصال', Colors.amber.shade700),
      MonitorState.error => ('قطع', Colors.red),
      MonitorState.stopped => ('متوقف', Colors.blueGrey),
    };
    return Tooltip(
      message: mon.error.value ?? '',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(.85),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
