import '../repositories/i_stream_repository.dart';

class StopStreamUseCase {
  final IStreamRepository repository;

  const StopStreamUseCase(this.repository);

  Future<void> call() async {
    return repository.stopStream();
  }
}
