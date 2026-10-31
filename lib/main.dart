import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'services/background_service.dart';
import 'services/monitor_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  if (Platform.isAndroid) {
    FlutterForegroundTask.initCommunicationPort();
    BackgroundService.init();
  }
  await manager.init();
  runApp(const DetectiveCameraApp());
}
