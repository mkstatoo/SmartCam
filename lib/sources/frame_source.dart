import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../core/frame.dart';

enum SourceState { connecting, live, error }

class SourceStatus {
  const SourceStatus(this.state, [this.message]);
  final SourceState state;
  final String? message;
}

/// منبع تصویر: هر نوع دوربین یک پیاده‌سازی دارد و فریم‌های کوچک‌شده
/// (عرض حدود ۳۲۰ پیکسل) را با نرخ دلخواه تحویل می‌دهد.
abstract class FrameSource {
  Stream<RgbFrame> get frames;
  Stream<SourceStatus> get status;
  Future<void> start();
  Future<void> stop();
}

/// پایهٔ مشترک: کنترلرها و ابزارهای کمکی.
abstract class BaseFrameSource implements FrameSource {
  final _frames = StreamController<RgbFrame>.broadcast();
  final _status = StreamController<SourceStatus>.broadcast();
  bool _closed = false;

  @override
  Stream<RgbFrame> get frames => _frames.stream;
  @override
  Stream<SourceStatus> get status => _status.stream;

  bool get closed => _closed;

  @protected
  void emitFrame(RgbFrame f) {
    if (!_closed) _frames.add(f);
  }

  @protected
  void emitStatus(SourceState s, [String? msg]) {
    if (!_closed) _status.add(SourceStatus(s, msg));
  }

  @protected
  Future<void> closeControllers() async {
    _closed = true;
    await _frames.close();
    await _status.close();
  }
}

/// عرض فریم‌های تحویلی به موتور تشخیص.
const int kFrameWidth = 320;

class _DecodeArgs {
  _DecodeArgs(this.bytes, this.width);
  final Uint8List bytes;
  final int width;
}

RgbFrame? _decodeJpegSync(_DecodeArgs a) {
  final im = img.decodeJpg(a.bytes);
  if (im == null) return null;
  final resized = im.width > a.width
      ? img.copyResize(
          im,
          width: a.width,
          interpolation: img.Interpolation.average,
        )
      : im;
  final rgb = resized
      .convert(numChannels: 3)
      .getBytes(order: img.ChannelOrder.rgb);
  return RgbFrame(resized.width, resized.height, Uint8List.fromList(rgb));
}

/// رمزگشایی JPEG و کوچک‌کردن در isolate جداگانه تا رابط کاربری قفل نشود.
Future<RgbFrame?> decodeJpegToFrame(
  Uint8List jpeg, {
  int width = kFrameWidth,
}) async {
  try {
    return await compute(_decodeJpegSync, _DecodeArgs(jpeg, width));
  } catch (_) {
    return null;
  }
}
