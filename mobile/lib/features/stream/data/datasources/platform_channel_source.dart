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
    required bool enableAudio,
  }) async {
    try {
      await _controlChannel.invokeMethod('startCapture', {
        'ip': ip,
        'port': port,
        'codec': codecIndex,
        'width': width,
        'height': height,
        'fps': fps,
        'enableAudio': enableAudio,
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

  /// Commands the native layer to switch camera direction (front/back).
  Future<void> switchCamera(bool useFront) async {
    try {
      await _controlChannel.invokeMethod('switchCamera', {'useFront': useFront});
    } catch (e) {
      print('[PlatformChannelSource] Error switching camera: $e');
    }
  }

  /// Commands the native layer to toggle camera flash.
  Future<void> toggleFlash(bool enable) async {
    try {
      await _controlChannel.invokeMethod('toggleFlash', {'enable': enable});
    } catch (e) {
      print('[PlatformChannelSource] Error toggling flash: $e');
    }
  }

  /// Retrieves list of supported camera resolutions with their maximum frame rates.
  Future<List<Map<String, dynamic>>> getSupportedResolutions() async {
    try {
      final List<dynamic>? res = await _controlChannel.invokeMethod('getSupportedResolutions');
      if (res != null) {
        return res.map((item) => Map<String, dynamic>.from(item as Map)).toList();
      }
    } catch (e) {
      // Return default fallbacks if error occurs or not supported
      print('[PlatformChannelSource] Error getting resolutions: $e');
    }
    return [
      {'width': 1920, 'height': 1080, 'maxFps': 60},
      {'width': 1280, 'height': 720, 'maxFps': 30},
      {'width': 640, 'height': 480, 'maxFps': 30},
    ];
  }
}
