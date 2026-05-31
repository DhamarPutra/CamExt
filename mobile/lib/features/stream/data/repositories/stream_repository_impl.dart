import 'dart:async';
import 'dart:typed_data';
import '../../domain/entities/connection_status.dart';
import '../../domain/entities/stream_config.dart';
import '../../domain/entities/stream_stats.dart';
import '../../domain/repositories/i_stream_repository.dart';
import '../datasources/platform_channel_source.dart';
import '../datasources/socket_egress_source.dart';

class StreamRepositoryImpl implements IStreamRepository {
  final PlatformChannelSource platformSource;
  final SocketEgressSource socketSource;

  final _statusController = StreamController<ConnectionStatus>.broadcast();
  final _statsController = StreamController<StreamStats>.broadcast();

  ConnectionStatus _status = ConnectionStatus.disconnected;
  StreamStats _stats = const StreamStats();
  StreamSubscription<Uint8List>? _frameSubscription;
  StreamSubscription<int>? _bytesSubscription;

  int _sequenceNumber = 0;
  int _frameCountInWindow = 0;
  int _bytesCountInWindow = 0;
  Timer? _statsTimer;
  DateTime? _lastStatsTime;

  StreamRepositoryImpl({
    required this.platformSource,
    required this.socketSource,
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
    _sequenceNumber = 0;
    _frameCountInWindow = 0;
    _bytesCountInWindow = 0;
    _stats = const StreamStats();
    _statsController.add(_stats);

    try {
      // 1. Hubungkan Soket Jaringan
      await socketSource.connect(config.ipAddress, config.port, config.protocol);

      // 2. Mulai tangkapan kamera & kompresi di tingkat Native / Mock
      final codecTypeVal = _getCodecTypeValue(config.codec);
      await platformSource.startCapture(
        codecIndex: codecTypeVal,
        width: config.width,
        height: config.height,
        fps: config.fps,
      );

      // 3. Berlangganan pengiriman frame -> soket
      _frameSubscription = platformSource.frameStream.listen((Uint8List frameData) {
        _sequenceNumber++;
        _frameCountInWindow++;
        
        final timestampUs = DateTime.now().microsecondsSinceEpoch;
        socketSource.sendFrame(frameData, _sequenceNumber, timestampUs, codecTypeVal);
      }, onError: (dynamic err) {
        stopStream();
      });

      // 4. Berlangganan statistik transmisi byte
      _bytesSubscription = socketSource.bytesSentStream.listen((int bytes) {
        _bytesCountInWindow += bytes;
      });

      _updateStatus(ConnectionStatus.connected);
      _startStatsCalculation();
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

    await _frameSubscription?.cancel();
    _frameSubscription = null;

    await _bytesSubscription?.cancel();
    _bytesSubscription = null;

    try {
      await platformSource.stopCapture();
    } catch (_) {}

    await socketSource.disconnect();
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

  void _startStatsCalculation() {
    _lastStatsTime = DateTime.now();
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final now = DateTime.now();
      final elapsedSec = now.difference(_lastStatsTime!).inMilliseconds / 1000.0;
      if (elapsedSec <= 0) return;

      final fps = _frameCountInWindow / elapsedSec;
      final mbps = ((_bytesCountInWindow * 8) / (1024 * 1024)) / elapsedSec;

      _stats = _stats.copyWith(
        currentFps: fps,
        dataRateMbps: mbps,
        totalFramesSent: _stats.totalFramesSent + _frameCountInWindow,
        totalBytesSent: _stats.totalBytesSent + _bytesCountInWindow,
      );

      _statsController.add(_stats);

      // Reset window metrics
      _frameCountInWindow = 0;
      _bytesCountInWindow = 0;
      _lastStatsTime = now;
    });
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
