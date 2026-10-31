import 'dart:io';

import 'package:flutter/material.dart';

import '../models/detection_event.dart';
import '../services/monitor_manager.dart';

/// صفحهٔ هشدار تمام‌صفحهٔ چشمک‌زن برای آتش/دود، تا وقتی کاربر آژیر را خاموش کند.
class AlarmOverlay extends StatefulWidget {
  const AlarmOverlay({super.key, required this.event});
  final DetectionEvent event;

  @override
  State<AlarmOverlay> createState() => _AlarmOverlayState();
}

class _AlarmOverlayState extends State<AlarmOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    final fire = e.kind == EventKind.fire;
    final title = fire ? 'هشدار آتش‌سوزی!' : 'هشدار دود!';
    return Material(
      color: Colors.transparent,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, child) => ColoredBox(
          color: Color.lerp(
            const Color(0xFF7A0000),
            const Color(0xFFD00000),
            _c.value,
          )!,
          child: child,
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  fire ? Icons.local_fire_department : Icons.cloud,
                  size: 96,
                  color: Colors.white,
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'دوربین: ${e.cameraName}',
                  style: const TextStyle(fontSize: 20, color: Colors.white),
                ),
                Text(
                  _fmt(e.time),
                  style: const TextStyle(fontSize: 14, color: Colors.white70),
                ),
                const SizedBox(height: 16),
                if (e.snapshotPath != null)
                  Flexible(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        File(e.snapshotPath!),
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.red.shade900,
                    ),
                    onPressed: () => manager.silenceAll(),
                    icon: const Icon(Icons.volume_off),
                    label: const Text(
                      'خاموش کردن آژیر',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'قبل از هر کاری از امن بودن خودتان مطمئن شوید و در صورت لزوم با ۱۲۵ تماس بگیرید.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _fmt(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  final l = t.toLocal();
  return '${l.year}-${two(l.month)}-${two(l.day)}  ${two(l.hour)}:${two(l.minute)}:${two(l.second)}';
}
