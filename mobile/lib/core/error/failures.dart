abstract class Failure {
  final String message;
  const Failure(this.message);
}

class SocketFailure extends Failure {
  const SocketFailure(super.message);
}

class CameraFailure extends Failure {
  const CameraFailure(super.message);
}

class EncoderFailure extends Failure {
  const EncoderFailure(super.message);
}

class UnknownFailure extends Failure {
  const UnknownFailure(super.message);
}
