import 'dart:async';
import 'package:flutter/services.dart';

class PlatformChannelSource {
  static final PlatformChannelSource _instance = PlatformChannelSource._internal();

  factory PlatformChannelSource() {
    return _instance;
  }

  PlatformChannelSource._internal();

  static const MethodChannel _controlChannel =
      MethodChannel('com.fujiwaracreative.camext/control');

  /// Commands the native layer to start camera capture, hardware encoding, and streaming.
  Future<void> startCapture({
    required String ip,
    required int port,
    required int codecIndex,
    required int width,
    required int height,
    required int fps,
  }) async {
    try {
      await _controlChannel.invokeMethod('startCapture', {
        'ip': ip,
        'port': port,
        'codec': codecIndex,
        'width': width,
        'height': height,
        'fps': fps,
      });
    } catch (e) {
      rethrow;
    }
  }

  /// Commands the native layer to stop capture and encoding.
  Future<void> stopCapture() async {
    try {
      await _controlChannel.invokeMethod('stopCapture');
    } catch (_) {}
  }
}
