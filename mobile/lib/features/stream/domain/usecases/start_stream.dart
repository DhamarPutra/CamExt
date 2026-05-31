import '../entities/stream_config.dart';
import '../repositories/i_stream_repository.dart';

class StartStreamUseCase {
  final IStreamRepository repository;

  const StartStreamUseCase(this.repository);

  Future<void> call(StreamConfig config) async {
    return repository.startStream(config);
  }
}
