class StreamStats {
  final double currentFps;
  final double dataRateMbps; // Megabits per second
  final int totalFramesSent;
  final int totalBytesSent;
  final int framesDropped;

  const StreamStats({
    this.currentFps = 0.0,
    this.dataRateMbps = 0.0,
    this.totalFramesSent = 0,
    this.totalBytesSent = 0,
    this.framesDropped = 0,
  });

  StreamStats copyWith({
    double? currentFps,
    double? dataRateMbps,
    int? totalFramesSent,
    int? totalBytesSent,
    int? framesDropped,
  }) {
    return StreamStats(
      currentFps: currentFps ?? this.currentFps,
      dataRateMbps: dataRateMbps ?? this.dataRateMbps,
      totalFramesSent: totalFramesSent ?? this.totalFramesSent,
      totalBytesSent: totalBytesSent ?? this.totalBytesSent,
      framesDropped: framesDropped ?? this.framesDropped,
    );
  }
}
