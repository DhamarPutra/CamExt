enum VideoCodec {
  mjpeg,
  h264,
  h265,
}

enum ConnectionProtocol {
  tcp,
  udp,
}

class StreamConfig {
  final String ipAddress;
  final int port;
  final VideoCodec codec;
  final ConnectionProtocol protocol;
  final int width;
  final int height;
  final int fps;

  const StreamConfig({
    required this.ipAddress,
    required this.port,
    required this.codec,
    required this.protocol,
    this.width = 1920,
    this.height = 1080,
    this.fps = 60,
  });

  StreamConfig copyWith({
    String? ipAddress,
    int? port,
    VideoCodec? codec,
    ConnectionProtocol? protocol,
    int? width,
    int? height,
    int? fps,
  }) {
    return StreamConfig(
      ipAddress: ipAddress ?? this.ipAddress,
      port: port ?? this.port,
      codec: codec ?? this.codec,
      protocol: protocol ?? this.protocol,
      width: width ?? this.width,
      height: height ?? this.height,
      fps: fps ?? this.fps,
    );
  }
}
