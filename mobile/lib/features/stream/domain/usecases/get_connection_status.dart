import '../entities/connection_status.dart';
import '../repositories/i_stream_repository.dart';

class GetConnectionStatusUseCase {
  final IStreamRepository repository;

  const GetConnectionStatusUseCase(this.repository);

  Stream<ConnectionStatus> call() {
    return repository.getConnectionStatus();
  }
}
