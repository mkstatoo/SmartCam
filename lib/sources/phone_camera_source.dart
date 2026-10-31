import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';

import '../core/frame.dart';
import 'frame_source.dart';

/// دوربین خود گوشی (مثلاً گوشی قدیمی که به‌عنوان دوربین مداربسته نصب شده).
class PhoneCameraSource extends BaseFrameSource {
  PhoneCameraSource({this.cameraIndex = 0, this.fps = 2});

  final int cameraIndex;
  final double fps;

  CameraController? _controller;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  Future<void> start() async {
    emitStatus(SourceState.connecting);
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        emitStatus(SourceState.error, 'دوربینی روی این دستگاه پیدا نشد');
        return;
      }
      final cam = cams[cameraIndex.clamp(0, cams.length - 1)];
      final c = CameraController(
        cam,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.yuv420
            : ImageFormatGroup.bgra8888,
      );
      _controller = c;
      await c.initialize();
      final gap = Duration(milliseconds: (1000 / fps.clamp(0.2, 5)).round());
      await c.startImageStream((CameraImage image) {
        final now = DateTime.now();
        if (now.difference(_last) < gap) return;
        _last = now;
        try {
          final f = _convert(image);
          emitStatus(SourceState.live);
          emitFrame(f);
        } catch (e) {
          emitStatus(SourceState.error, '$e');
        }
      });
    } catch (e) {
      emitStatus(SourceState.error, '$e');
    }
  }

  RgbFrame _convert(CameraImage image) {
    if (image.format.group == ImageFormatGroup.yuv420 &&
        image.planes.length >= 3) {
      final p = image.planes;
      return RgbFrame.fromYuv420(
        srcWidth: image.width,
        srcHeight: image.height,
        y: p[0].bytes,
        u: p[1].bytes,
        v: p[2].bytes,
        yRowStride: p[0].bytesPerRow,
        uvRowStride: p[1].bytesPerRow,
        uvPixelStride: p[1].bytesPerPixel ?? 1,
        targetWidth: kFrameWidth,
      );
    }
    // iOS: BGRA8888
    final plane = image.planes.first;
    final tw = kFrameWidth.clamp(1, image.width);
    final th = (image.height * tw / image.width).round().clamp(1, image.height);
    final out = Uint8List(tw * th * 3);
    final bytes = plane.bytes;
    var o = 0;
    for (var y = 0; y < th; y++) {
      final sy = ((y + 0.5) * image.height / th).floor().clamp(
        0,
        image.height - 1,
      );
      for (var x = 0; x < tw; x++) {
        final sx = ((x + 0.5) * image.width / tw).floor().clamp(
          0,
          image.width - 1,
        );
        final i = sy * plane.bytesPerRow + sx * 4;
        out[o++] = bytes[i + 2];
        out[o++] = bytes[i + 1];
        out[o++] = bytes[i];
      }
    }
    return RgbFrame(tw, th, out);
  }

  @override
  Future<void> stop() async {
    final c = _controller;
    _controller = null;
    try {
      if (c != null && c.value.isStreamingImages) await c.stopImageStream();
    } catch (_) {}
    try {
      await c?.dispose();
    } catch (_) {}
    await closeControllers();
  }
}
