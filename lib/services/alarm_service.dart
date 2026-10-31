import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:vibration/vibration.dart';

import '../models/app_settings.dart';

/// آژیر و بوق: آژیر تا زمانی که کاربر خاموش کند (یا زمان خودکار تمام شود)
/// تکرار می‌شود.
class AlarmService {
  AlarmService(this.settings);

  AppSettings settings;

  final AudioPlayer _siren = AudioPlayer(playerId: 'siren');
  final AudioPlayer _beep = AudioPlayer(playerId: 'beep');
  Timer? _autoStop;
  bool _ready = false;

  /// آیا آژیر الان در حال پخش است؟
  final ValueNotifier<bool> sirenOn = ValueNotifier(false);

  Future<void> _init() async {
    if (_ready) return;
    _ready = true;
    try {
      // پخش با کانال «آلارم» اندروید تا حتی در حالت بی‌صدا هم شنیده شود (در حد مجاز سیستم).
      final ctx = AudioContext(
        android: const AudioContextAndroid(
          usageType: AndroidUsageType.alarm,
          contentType: AndroidContentType.sonification,
          audioFocus: AndroidAudioFocus.gain,
        ),
        iOS: AudioContextIOS(category: AVAudioSessionCategory.playback),
      );
      await _siren.setAudioContext(ctx);
      await _beep.setAudioContext(ctx);
    } catch (_) {}
    await _siren.setReleaseMode(ReleaseMode.loop);
  }

  Future<void> startSiren() async {
    await _init();
    if (sirenOn.value) return;
    sirenOn.value = true;
    try {
      await _siren.setVolume(settings.sirenVolume.clamp(0.0, 1.0));
      await _siren.play(AssetSource('sounds/siren.wav'));
    } catch (_) {}
    if (settings.vibrate) {
      try {
        if (await Vibration.hasVibrator() ?? false) {
          Vibration.vibrate(pattern: [0, 800, 400, 800, 400], repeat: 0);
        }
      } catch (_) {}
    }
    _autoStop?.cancel();
    final m = settings.sirenAutoStopMinutes;
    if (m > 0) _autoStop = Timer(Duration(minutes: m), stopSiren);
  }

  Future<void> stopSiren() async {
    _autoStop?.cancel();
    if (!sirenOn.value) return;
    sirenOn.value = false;
    try {
      await _siren.stop();
    } catch (_) {}
    try {
      await Vibration.cancel();
    } catch (_) {}
  }

  Future<void> beep() async {
    await _init();
    try {
      await _beep.setVolume(1.0);
      await _beep.play(AssetSource('sounds/beep.wav'));
    } catch (_) {}
    if (settings.vibrate) {
      try {
        Vibration.vibrate(duration: 400);
      } catch (_) {}
    }
  }

  /// صدای مناسب برای هشدار حرکت طبق تنظیمات.
  Future<void> motionAlert() async {
    switch (settings.motionSound) {
      case MotionSound.silent:
        return;
      case MotionSound.beep:
        return beep();
      case MotionSound.siren:
        return startSiren();
    }
  }

  Future<void> dispose() async {
    await stopSiren();
    await _siren.dispose();
    await _beep.dispose();
  }
}
