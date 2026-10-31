import 'dart:io';

import 'package:flutter/material.dart';

import '../models/detection_event.dart';
import '../services/monitor_manager.dart';

class EventsPage extends StatelessWidget {
  const EventsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        final list = manager.events;
        return Scaffold(
          appBar: AppBar(
            title: const Text('رویدادها'),
            actions: [
              if (list.isNotEmpty)
                IconButton(
                  tooltip: 'پاک کردن همه',
                  icon: const Icon(Icons.delete_sweep_outlined),
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('پاک کردن همهٔ رویدادها'),
                        content: const Text('تصاویر ذخیره‌شده هم حذف می‌شوند.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('انصراف'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('پاک کن'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) manager.clearEvents();
                  },
                ),
            ],
          ),
          body: list.isEmpty
              ? const Center(
                  child: Text(
                    'هنوز رویدادی ثبت نشده است',
                    style: TextStyle(color: Colors.white54),
                  ),
                )
              : ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) => _EventTile(event: list[i]),
                ),
        );
      },
    );
  }
}

Color _color(EventKind k) => switch (k) {
  EventKind.fire => Colors.redAccent,
  EventKind.smoke => Colors.amber,
  EventKind.motion => Colors.lightGreenAccent,
  EventKind.offline => Colors.blueGrey,
  EventKind.online => Colors.lightBlueAccent,
};

IconData _icon(EventKind k) => switch (k) {
  EventKind.fire => Icons.local_fire_department,
  EventKind.smoke => Icons.cloud,
  EventKind.motion => Icons.directions_run,
  EventKind.offline => Icons.wifi_off,
  EventKind.online => Icons.wifi,
};

String fmtTime(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  final l = t.toLocal();
  return '${l.year}-${two(l.month)}-${two(l.day)}  ${two(l.hour)}:${two(l.minute)}:${two(l.second)}';
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event});
  final DetectionEvent event;

  @override
  Widget build(BuildContext context) {
    final e = event;
    final path = e.snapshotPath;
    return ListTile(
      leading: SizedBox(
        width: 72,
        height: 48,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: path != null && File(path).existsSync()
              ? Image.file(File(path), fit: BoxFit.cover)
              : ColoredBox(
                  color: Colors.black,
                  child: Icon(_icon(e.kind), color: _color(e.kind)),
                ),
        ),
      ),
      title: Row(
        children: [
          Icon(_icon(e.kind), size: 16, color: _color(e.kind)),
          const SizedBox(width: 6),
          Text(
            eventKindLabel(e.kind),
            style: TextStyle(
              fontWeight: e.acknowledged ? FontWeight.w400 : FontWeight.w800,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              e.cameraName,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white60, fontSize: 13),
            ),
          ),
        ],
      ),
      subtitle: Text(
        fmtTime(e.time),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.right,
        style: const TextStyle(fontSize: 12),
      ),
      trailing: e.acknowledged || !isCritical(e.kind)
          ? null
          : const Icon(Icons.priority_high, color: Colors.redAccent),
      onTap: () => _open(context),
    );
  }

  void _open(BuildContext context) {
    final e = event;
    final path = e.snapshotPath;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${eventKindLabel(e.kind)} — ${e.cameraName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (path != null && File(path).existsSync())
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(File(path)),
              ),
            const SizedBox(height: 8),
            Text(fmtTime(e.time), textDirection: TextDirection.ltr),
          ],
        ),
        actions: [
          if (!e.acknowledged)
            TextButton(
              onPressed: () {
                manager.acknowledge(e);
                Navigator.pop(context);
              },
              child: const Text('دیدم'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('بستن'),
          ),
        ],
      ),
    );
  }
}
