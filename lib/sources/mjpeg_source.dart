import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../core/mjpeg_parser.dart';
import 'frame_source.dart';
import 'http_auth.dart';

/// جریان MJPEG روی HTTP. همهٔ فریم‌ها خوانده می‌شوند ولی فقط با نرخ [fps]
/// رمزگشایی و تحلیل می‌شوند (بقیه دور ریخته می‌شوند تا CPU مصرف نشود).
class MjpegSource extends BaseFrameSource {
  MjpegSource({
    required this.url,
    this.username = '',
    this.password = '',
    this.fps = 2,
  });

  final String url;
  final String username, password;
  final double fps;

  final MjpegParser _parser = MjpegParser();
  HttpClient? _client;
  StreamSubscription<List<int>>? _sub;
  DateTime _lastTaken = DateTime.fromMillisecondsSinceEpoch(0);
  bool _decoding = false;
  Timer? _watch;
  DateTime _lastData = DateTime.now();

  @override
  Future<void> start() async {
    emitStatus(SourceState.connecting);
    try {
      _client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      final resp = await authedGet(
        _client!,
        Uri.parse(url),
        username: username,
        password: password,
      );
      if (resp.statusCode != 200) {
        await resp.drain<void>();
        emitStatus(SourceState.error, 'پاسخ سرور: ${resp.statusCode}');
        return;
      }
      final minGap = Duration(milliseconds: (1000 / fps.clamp(0.2, 5)).round());
      _lastData = DateTime.now();
      _sub = resp.listen(
        (chunk) {
          _lastData = DateTime.now();
          final frames = _parser.add(chunk);
          if (frames.isEmpty) return;
          final now = DateTime.now();
          if (_decoding || now.difference(_lastTaken) < minGap) return;
          _lastTaken = now;
          _decoding = true;
          final Uint8List jpeg = frames.last;
          decodeJpegToFrame(jpeg).then((f) {
            _decoding = false;
            if (f != null) {
              emitStatus(SourceState.live);
              emitFrame(f);
            }
          });
        },
        onError: (Object e) => emitStatus(SourceState.error, '$e'),
        onDone: () => emitStatus(SourceState.error, 'اتصال بسته شد'),
        cancelOnError: true,
      );
      // اگر مدتی داده نیامد، خطا اعلام شود تا مانیتور دوباره وصل شود.
      _watch = Timer.periodic(const Duration(seconds: 5), (_) {
        if (DateTime.now().difference(_lastData) >
            const Duration(seconds: 15)) {
          emitStatus(SourceState.error, 'دادهای دریافت نمی‌شود');
        }
      });
    } catch (e) {
      emitStatus(SourceState.error, '$e');
    }
  }

  @override
  Future<void> stop() async {
    _watch?.cancel();
    await _sub?.cancel();
    _client?.close(force: true);
    await closeControllers();
  }
}
