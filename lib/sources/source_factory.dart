import 'dart:async';

import '../core/frame.dart';
import '../models/camera_config.dart';
import 'frame_source.dart';
import 'mjpeg_source.dart';
import 'phone_camera_source.dart';
import 'snapshot_source.dart';
import 'stream_source.dart';

FrameSource createSource(CameraConfig c) {
  switch (c.type) {
    case SourceType.stream:
      return StreamSource(url: c.effectiveUrl, fps: c.fps);
    case SourceType.mjpeg:
      return MjpegSource(
        url: c.url,
        username: c.username,
        password: c.password,
        fps: c.fps,
      );
    case SourceType.snapshot:
      return SnapshotSource(
        url: c.url,
        username: c.username,
        password: c.password,
        fps: c.fps,
      );
    case SourceType.phone:
      return PhoneCameraSource(cameraIndex: c.phoneCameraIndex, fps: c.fps);
  }
}

class SourceTestResult {
  const SourceTestResult.ok(this.frame) : error = null;
  const SourceTestResult.fail(this.error) : frame = null;
  final RgbFrame? frame;
  final String? error;
  bool get ok => frame != null;
}

/// اتصال آزمایشی: تا ۲۰ ثانیه برای دریافت اولین فریم صبر می‌کند.
Future<SourceTestResult> testSource(CameraConfig c) async {
  final src = createSource(c);
  final done = Completer<SourceTestResult>();
  String? lastErr;
  final s1 = src.frames.listen((f) {
    if (!done.isCompleted) done.complete(SourceTestResult.ok(f));
  });
  final s2 = src.status.listen((s) {
    if (s.state == SourceState.error) lastErr = s.message;
  });
  try {
    await src.start();
    return await done.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () => SourceTestResult.fail(lastErr ?? 'پاسخی دریافت نشد'),
    );
  } finally {
    await s1.cancel();
    await s2.cancel();
    await src.stop();
  }
}
