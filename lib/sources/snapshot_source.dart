import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'frame_source.dart';
import 'http_auth.dart';

/// دریافت دوره‌ای یک عکس JPEG از آدرس HTTP
/// (مثلاً http://192.168.1.20/snapshot.jpg یا /shot.jpg در «IP Webcam»).
class SnapshotSource extends BaseFrameSource {
  SnapshotSource({
    required this.url,
    this.username = '',
    this.password = '',
    this.fps = 1,
  });

  final String url;
  final String username, password;
  final double fps;

  Timer? _timer;
  bool _busy = false;
  int _failures = 0;
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8);

  @override
  Future<void> start() async {
    emitStatus(SourceState.connecting);
    final ms = (1000 / fps.clamp(0.2, 5)).round();
    _timer = Timer.periodic(Duration(milliseconds: ms), (_) => _tick());
    unawaited(_tick());
  }

  Future<void> _tick() async {
    if (_busy || closed) return;
    _busy = true;
    try {
      final uri = Uri.parse(url);
      final resp = await authedGet(
        _client,
        uri,
        username: username,
        password: password,
      );
      if (resp.statusCode != 200) {
        await resp.drain<void>();
        throw HttpException('HTTP ${resp.statusCode}');
      }
      final bb = BytesBuilder(copy: false);
      await for (final c in resp.timeout(const Duration(seconds: 10))) {
        bb.add(c);
        if (bb.length > 8 * 1024 * 1024) throw const FormatException('too big');
      }
      final frame = await decodeJpegToFrame(bb.takeBytes());
      if (frame == null) throw const FormatException('تصویر JPEG معتبر نیست');
      _failures = 0;
      emitStatus(SourceState.live);
      emitFrame(frame);
    } catch (e) {
      _failures++;
      if (_failures >= 3) emitStatus(SourceState.error, '$e');
    } finally {
      _busy = false;
    }
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _client.close(force: true);
    await closeControllers();
  }
}
