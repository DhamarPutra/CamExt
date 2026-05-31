import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';

class PlatformChannelSource {
  static final PlatformChannelSource _instance = PlatformChannelSource._internal();

  factory PlatformChannelSource() {
    return _instance;
  }

  PlatformChannelSource._internal();

  static const MethodChannel _controlChannel =
      MethodChannel('com.fujiwaracreative.camext/control');
  static const EventChannel _frameChannel =
      EventChannel('com.fujiwaracreative.camext/stream');

  StreamController<Uint8List>? _frameController;
  Timer? _mockTimer;
  bool _useMock = true;

  /// Call native platform method to convert YUV camera planes to compressed JPEG
  Future<Uint8List> yuvToJpeg({
    required Uint8List y,
    required Uint8List u,
    required Uint8List v,
    required int yRowStride,
    required int uRowStride,
    required int vRowStride,
    required int uPixelStride,
    required int vPixelStride,
    required int width,
    required int height,
    int quality = 70,
    int rotation = 0,
  }) async {
    final result = await _controlChannel.invokeMethod<Uint8List>('yuvToJpeg', {
      'y': y,
      'u': u,
      'v': v,
      'yRowStride': yRowStride,
      'uRowStride': uRowStride,
      'vRowStride': vRowStride,
      'uPixelStride': uPixelStride,
      'vPixelStride': vPixelStride,
      'width': width,
      'height': height,
      'quality': quality,
      'rotation': rotation,
    });
    return result!;
  }

  /// Injects a live physical camera frame directly into the egress pipeline
  void injectFrame(Uint8List frameBytes) {
    _useMock = false;
    _mockTimer?.cancel();
    if (_frameController != null && !_frameController!.isClosed) {
      _frameController!.add(frameBytes);
    }
  }

  /// Commands the native layer to start camera capture and hardware encoding.
  /// [codecIndex] maps to: 1 = MJPEG, 2 = H.264, 3 = H.265
  Future<void> startCapture({
    required int codecIndex,
    required int width,
    required int height,
    required int fps,
  }) async {
    _useMock = true;

    // Jalankan start capture native (untuk compatibility)
    try {
      await _controlChannel.invokeMethod('startCapture', {
        'codec': codecIndex,
        'width': width,
        'height': height,
        'fps': fps,
      });
    } catch (_) {}

    // BACA GAMBAR JPEG NYATA DARI ASSETS DART
    final ByteData data = await rootBundle.load('assets/frame.jpg');
    final Uint8List jpegBytes = data.buffer.asUint8List();

    // Hentikan timer simulasi sebelumnya jika masih aktif
    _mockTimer?.cancel();
    _frameController?.close();

    // Buat stream controller baru untuk mengirim JPEG asli ke Socket
    _frameController = StreamController<Uint8List>.broadcast();

    // Jalankan timer 30 FPS untuk menembakkan JPEG simulasi secara berkelanjutan (selama kamera fisik belum menginjeksikan data)
    final intervalMs = 1000 ~/ fps;
    _mockTimer = Timer.periodic(Duration(milliseconds: intervalMs), (timer) {
      if (_useMock && _frameController != null && !_frameController!.isClosed) {
        _frameController!.add(jpegBytes);
      }
    });
  }

  /// Commands the native layer to stop capture and encoding.
  Future<void> stopCapture() async {
    _mockTimer?.cancel();
    _mockTimer = null;
    _frameController?.close();
    _frameController = null;

    try {
      await _controlChannel.invokeMethod('stopCapture');
    } catch (_) {}
  }

  /// Listens to the compressed frame packets emitted from the native MediaCodec/VideoToolbox.
  Stream<Uint8List> get frameStream {
    if (_frameController != null) {
      return _frameController!.stream;
    }

    // Fallback ke Event Channel native
    return _frameChannel
        .receiveBroadcastStream()
        .map<Uint8List>((dynamic event) => event as Uint8List);
  }
}
