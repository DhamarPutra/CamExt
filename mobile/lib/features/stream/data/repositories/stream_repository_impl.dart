import 'dart:async';
import '../../domain/entities/connection_status.dart';
import '../../domain/entities/stream_config.dart';
import '../../domain/entities/stream_stats.dart';
import '../../domain/repositories/i_stream_repository.dart';
import '../datasources/platform_channel_source.dart';

class StreamRepositoryImpl implements IStreamRepository {
  final PlatformChannelSource platformSource;

  final _statusController = StreamController<ConnectionStatus>.broadcast();
  final _statsController = StreamController<StreamStats>.broadcast();

  ConnectionStatus _status = ConnectionStatus.disconnected;
  StreamStats _stats = const StreamStats();
  Timer? _statsTimer;
  DateTime? _lastStatsTime;

  StreamRepositoryImpl({
    required this.platformSource,
  }) {
    _statusController.add(_status);
    _statsController.add(_stats);
  }

  @override
  Future<void> startStream(StreamConfig config) async {
    if (_status == ConnectionStatus.connected || _status == ConnectionStatus.connecting) {
      return;
    }

    _updateStatus(ConnectionStatus.connecting);
    _stats = const StreamStats();
    _statsController.add(_stats);

    try {
      final codecTypeVal = _getCodecTypeValue(config.codec);
      
      // Mulai tangkapan kamera & streaming native socket di Kotlin
      await platformSource.startCapture(
        ip: config.ipAddress,
        port: config.port,
        codecIndex: codecTypeVal,
        width: config.width,
        height: config.height,
        fps: config.fps,
        enableAudio: config.enableAudio,
      );

      _updateStatus(ConnectionStatus.connected);
      _startStatsCalculation(config);
    } catch (e) {
      _updateStatus(ConnectionStatus.failed);
      await stopStream();
      rethrow;
    }
  }

  @override
  Future<void> stopStream() async {
    _statsTimer?.cancel();
    _statsTimer = null;

    try {
      await platformSource.stopCapture();
    } catch (_) {}

    _updateStatus(ConnectionStatus.disconnected);
  }

  @override
  Stream<ConnectionStatus> getConnectionStatus() => _statusController.stream;

  @override
  Stream<StreamStats> getStreamStats() => _statsController.stream;

  void _updateStatus(ConnectionStatus newStatus) {
    _status = newStatus;
    _statusController.add(newStatus);
  }

  void _startStatsCalculation(StreamConfig config) {
    _lastStatsTime = DateTime.now();
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final now = DateTime.now();
      final elapsedSec = now.difference(_lastStatsTime!).inMilliseconds / 1000.0;
      if (elapsedSec <= 0) return;

      // Estimasi statistik transmisi biner berdasarkan konfigurasi aktif
      final targetFps = config.fps.toDouble();
      final estimatedMbps = config.width == 1920 ? 12.5 : (config.width == 1280 ? 6.5 : 3.0);

      _stats = _stats.copyWith(
        currentFps: targetFps,
        dataRateMbps: estimatedMbps,
        totalFramesSent: _stats.totalFramesSent + (targetFps * elapsedSec).toInt(),
        totalBytesSent: _stats.totalBytesSent + ((estimatedMbps * 1024 * 1024 / 8) * elapsedSec).toInt(),
      );

      _statsController.add(_stats);
      _lastStatsTime = now;
    });
  }

  @override
  Future<List<Map<String, dynamic>>> getSupportedResolutions() {
    return platformSource.getSupportedResolutions();
  }

  int _getCodecTypeValue(VideoCodec codec) {
    switch (codec) {
      case VideoCodec.mjpeg:
        return 1;
      case VideoCodec.h264:
        return 2;
      case VideoCodec.h265:
        return 3;
    }
  }
}
