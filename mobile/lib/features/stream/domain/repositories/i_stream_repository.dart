import '../entities/connection_status.dart';
import '../entities/stream_config.dart';
import '../entities/stream_stats.dart';

abstract class IStreamRepository {
  Future<void> startStream(StreamConfig config);
  Future<void> stopStream();
  Stream<StreamStats> getStreamStats();
  Stream<ConnectionStatus> getConnectionStatus();
}
