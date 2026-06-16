import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../domain/entities/connection_status.dart';
import '../../domain/entities/stream_config.dart';
import '../../domain/entities/stream_stats.dart';
import '../../domain/usecases/get_connection_status.dart';
import '../../domain/usecases/get_stream_stats.dart';
import '../../domain/usecases/start_stream.dart';
import '../../domain/usecases/stop_stream.dart';
import '../../data/datasources/platform_channel_source.dart';

class StreamState {
  final StreamConfig config;
  final ConnectionStatus status;
  final StreamStats stats;
  final String? errorMessage;
  final bool useFrontCamera;
  final bool flashEnabled;

  const StreamState({
    required this.config,
    this.status = ConnectionStatus.disconnected,
    this.stats = const StreamStats(),
    this.errorMessage,
    this.useFrontCamera = false,
    this.flashEnabled = false,
  });

  StreamState copyWith({
    StreamConfig? config,
    ConnectionStatus? status,
    StreamStats? stats,
    String? errorMessage,
    bool? useFrontCamera,
    bool? flashEnabled,
  }) {
    return StreamState(
      config: config ?? this.config,
      status: status ?? this.status,
      stats: stats ?? this.stats,
      errorMessage: errorMessage ?? this.errorMessage,
      useFrontCamera: useFrontCamera ?? this.useFrontCamera,
      flashEnabled: flashEnabled ?? this.flashEnabled,
    );
  }
}

class StreamNotifier extends ValueNotifier<StreamState> {
  final StartStreamUseCase startStreamUseCase;
  final StopStreamUseCase stopStreamUseCase;
  final GetStreamStatsUseCase getStreamStatsUseCase;
  final GetConnectionStatusUseCase getConnectionStatusUseCase;

  StreamSubscription<ConnectionStatus>? _statusSubscription;
  StreamSubscription<StreamStats>? _statsSubscription;

  StreamNotifier({
    required this.startStreamUseCase,
    required this.stopStreamUseCase,
    required this.getStreamStatsUseCase,
    required this.getConnectionStatusUseCase,
  }) : super(
          const StreamState(
            config: StreamConfig(
              ipAddress: '127.0.0.1',
              port: 4455,
              codec: VideoCodec.mjpeg,
              protocol: ConnectionProtocol.tcp,
              width: 1280,
              height: 720,
              fps: 30,
              enableAudio: false,
            ),
          ),
        );

  Future<void> startStreaming() async {
    if (value.status == ConnectionStatus.connected ||
        value.status == ConnectionStatus.connecting) {
      return;
    }

    value = value.copyWith(
      status: ConnectionStatus.connecting,
      errorMessage: null,
    );

    try {
      // 1. Mulai dengarkan status & stats
      _statusSubscription?.cancel();
      _statusSubscription = getConnectionStatusUseCase().listen((status) {
        value = value.copyWith(status: status);
      });

      _statsSubscription?.cancel();
      _statsSubscription = getStreamStatsUseCase().listen((stats) {
        value = value.copyWith(stats: stats);
      });

      // 2. Jalankan start stream
      await startStreamUseCase(value.config);
    } catch (e) {
      value = value.copyWith(
        status: ConnectionStatus.failed,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> stopStreaming() async {
    value = value.copyWith(status: ConnectionStatus.disconnected);
    await _statusSubscription?.cancel();
    _statusSubscription = null;
    await _statsSubscription?.cancel();
    _statsSubscription = null;

    await stopStreamUseCase();
  }

  void updateIpAddress(String ip) {
    value = value.copyWith(config: value.config.copyWith(ipAddress: ip));
  }

  void updatePort(int port) {
    value = value.copyWith(config: value.config.copyWith(port: port));
  }

  void updateCodec(VideoCodec codec) {
    value = value.copyWith(config: value.config.copyWith(codec: codec));
  }

  void updateProtocol(ConnectionProtocol protocol) {
    value = value.copyWith(config: value.config.copyWith(protocol: protocol));
  }

  void updateResolution(int width, int height) {
    value = value.copyWith(config: value.config.copyWith(width: width, height: height));
  }

  void updateResolutionAndFps(int width, int height, int fps) {
    value = value.copyWith(config: value.config.copyWith(width: width, height: height, fps: fps));
  }

  void toggleAudio(bool enable) {
    value = value.copyWith(config: value.config.copyWith(enableAudio: enable));
  }

  Future<void> toggleCamera() async {
    final nextUseFront = !value.useFrontCamera;
    value = value.copyWith(useFrontCamera: nextUseFront);
    await PlatformChannelSource().switchCamera(nextUseFront);
  }

  Future<void> toggleFlash() async {
    final nextFlash = !value.flashEnabled;
    value = value.copyWith(flashEnabled: nextFlash);
    await PlatformChannelSource().toggleFlash(nextFlash);
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    _statsSubscription?.cancel();
    super.dispose();
  }
}
