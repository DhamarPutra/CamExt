import '../entities/stream_stats.dart';
import '../repositories/i_stream_repository.dart';

class GetStreamStatsUseCase {
  final IStreamRepository repository;

  const GetStreamStatsUseCase(this.repository);

  Stream<StreamStats> call() {
    return repository.getStreamStats();
  }
}
