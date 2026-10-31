import 'dart:async';

import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'frame_source.dart';

/// RTSP / RTMP / HLS / HTTP-FLV و هر آدرسی که libmpv/FFmpeg بتواند باز کند.
/// تصویر پخش می‌شود (بی‌صدا) و با نرخ [fps] از آن عکس گرفته می‌شود.
class StreamSource extends BaseFrameSource {
  StreamSource({required this.url, this.fps = 2});

  final String url;
  final double fps;

  Player? _player;
  // نگه‌داشتن کنترلر لازم است تا خروجی تصویر ساخته شود و screenshot کار کند.
  // ignore: unused_field
  VideoController? _video;
  Timer? _timer;
  bool _busy = false;
  DateTime _openedAt = DateTime.now();
  int _noVideoTicks = 0;
  StreamSubscription<String>? _errSub;

  @override
  Future<void> start() async {
    emitStatus(SourceState.connecting);
    try {
      final p = Player(
        configuration: const PlayerConfiguration(
          bufferSize: 4 * 1024 * 1024,
          logLevel: MPVLogLevel.error,
        ),
      );
      _player = p;
      _video = VideoController(p);
      await p.setVolume(0);

      final platform = p.platform;
      if (platform is NativePlayer) {
        // RTSP روی TCP (پایدارتر از UDP روی Wi-Fi)، تأخیر کم، تایم‌اوت شبکه
        await platform.setProperty('demuxer-lavf-o', 'rtsp_transport=tcp');
        await platform.setProperty('network-timeout', '10');
        await platform.setProperty('profile', 'low-latency');
        await platform.setProperty('cache', 'no');
      }
      _errSub = p.stream.error.listen((e) {
        if (e.isNotEmpty) emitStatus(SourceState.error, e);
      });

      _openedAt = DateTime.now();
      await p.open(Media(url), play: true);

      final ms = (1000 / fps.clamp(0.2, 5)).round();
      _timer = Timer.periodic(Duration(milliseconds: ms), (_) => _tick());
    } catch (e) {
      emitStatus(SourceState.error, '$e');
    }
  }

  Future<void> _tick() async {
    final p = _player;
    if (p == null || _busy || closed) return;
    final hasVideo = (p.state.width ?? 0) > 0 && (p.state.height ?? 0) > 0;
    if (!hasVideo) {
      _noVideoTicks++;
      if (DateTime.now().difference(_openedAt) > const Duration(seconds: 20)) {
        emitStatus(
          SourceState.error,
          'تصویری دریافت نشد (آدرس/رمز را بررسی کنید)',
        );
      }
      return;
    }
    _busy = true;
    try {
      final jpeg = await p.screenshot(format: 'image/jpeg');
      if (jpeg == null || jpeg.isEmpty) return;
      final f = await decodeJpegToFrame(jpeg);
      if (f != null) {
        _noVideoTicks = 0;
        emitStatus(SourceState.live);
        emitFrame(f);
      }
    } catch (e) {
      emitStatus(SourceState.error, '$e');
    } finally {
      _busy = false;
    }
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    await _errSub?.cancel();
    try {
      await _player?.dispose();
    } catch (_) {}
    _player = null;
    _video = null;
    await closeControllers();
  }
}
