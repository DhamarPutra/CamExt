import 'dart:typed_data';

class PacketHeader {
  static const int headerSize = 20;
  static const int magicHeader = 0xCA5ECA5E;

  final int sequenceNumber;
  final int timestampUs;
  final int codecType; // 1 = MJPEG, 2 = H.264, 3 = H.265
  final int payloadSize;

  const PacketHeader({
    required this.sequenceNumber,
    required this.timestampUs,
    required this.codecType,
    required this.payloadSize,
  });

  /// Serializes the header fields into a 20-byte Uint8List in network byte order (Big-Endian).
  Uint8List toBytes() {
    final buffer = Uint8List(headerSize);
    final byteData = ByteData.sublistView(buffer);

    // 0 - 3: Magic Header
    byteData.setUint32(0, magicHeader, Endian.big);
    // 4 - 7: Sequence Number
    byteData.setUint32(4, sequenceNumber, Endian.big);
    // 8 - 11: Timestamp (microseconds)
    byteData.setUint32(8, timestampUs, Endian.big);
    // 12: Codec Type
    byteData.setUint8(12, codecType);
    // 13 - 15: Reserved (Zero-filled padding)
    byteData.setUint8(13, 0);
    byteData.setUint8(14, 0);
    byteData.setUint8(15, 0);
    // 16 - 19: Payload Size
    byteData.setUint32(16, payloadSize, Endian.big);

    return buffer;
  }

  /// Parses a 20-byte Uint8List back into a PacketHeader.
  factory PacketHeader.fromBytes(Uint8List bytes) {
    if (bytes.length < headerSize) {
      throw ArgumentError('Invalid header size. Must be at least 20 bytes.');
    }

    final byteData = ByteData.sublistView(bytes);
    final magic = byteData.getUint32(0, Endian.big);
    if (magic != magicHeader) {
      throw FormatException('Invalid magic header. Got: 0x${magic.toRadixString(16).toUpperCase()}');
    }

    final seq = byteData.getUint32(4, Endian.big);
    final ts = byteData.getUint32(8, Endian.big);
    final codec = byteData.getUint8(12);
    final size = byteData.getUint32(16, Endian.big);

    return PacketHeader(
      sequenceNumber: seq,
      timestampUs: ts,
      codecType: codec,
      payloadSize: size,
    );
  }
}
