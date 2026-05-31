import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import '../../domain/entities/stream_config.dart';
import '../models/packet_header.dart';

class SocketEgressSource {
  Socket? _tcpSocket;
  RawDatagramSocket? _udpSocket;
  InternetAddress? _targetAddress;
  int? _targetPort;
  ConnectionProtocol? _protocol;

  final _bytesSentController = StreamController<int>.broadcast();
  Stream<int> get bytesSentStream => _bytesSentController.stream;

  bool _isConnecting = false;
  bool get isConnected => _tcpSocket != null || _udpSocket != null;

  Future<void> connect(String ipAddress, int port, ConnectionProtocol protocol) async {
    if (isConnected || _isConnecting) return;
    _isConnecting = true;
    _protocol = protocol;
    _targetPort = port;

    try {
      _targetAddress = (await InternetAddress.lookup(ipAddress)).first;

      if (protocol == ConnectionProtocol.tcp) {
        _tcpSocket = await Socket.connect(
          _targetAddress,
          port,
          timeout: const Duration(seconds: 5),
        );
        _tcpSocket!.setOption(SocketOption.tcpNoDelay, true); // Ultra low latency TCP
      } else {
        // UDP connectionless setup
        _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      }
    } catch (e) {
      await disconnect();
      rethrow;
    } finally {
      _isConnecting = false;
    }
  }

  /// Sends a video frame package consisting of the 20-byte header + compressed video payload.
  void sendFrame(Uint8List payload, int sequenceNumber, int timestampUs, int codecType) {
    if (!isConnected) return;

    final header = PacketHeader(
      sequenceNumber: sequenceNumber,
      timestampUs: timestampUs,
      codecType: codecType,
      payloadSize: payload.length,
    ).toBytes();

    final fullPacket = BytesBuilder(copy: false)
      ..add(header)
      ..add(payload);

    final data = fullPacket.takeBytes();

    if (_protocol == ConnectionProtocol.tcp && _tcpSocket != null) {
      try {
        _tcpSocket!.add(data);
        _bytesSentController.add(data.length);
      } catch (e) {
        // Handle socket errors gracefully
      }
    } else if (_protocol == ConnectionProtocol.udp && _udpSocket != null && _targetAddress != null && _targetPort != null) {
      try {
        _udpSocket!.send(data, _targetAddress!, _targetPort!);
        _bytesSentController.add(data.length);
      } catch (e) {
        // Handle socket errors gracefully
      }
    }
  }

  Future<void> disconnect() async {
    try {
      if (_tcpSocket != null) {
        await _tcpSocket!.flush();
        await _tcpSocket!.close();
        _tcpSocket = null;
      }
      if (_udpSocket != null) {
        _udpSocket!.close();
        _udpSocket = null;
      }
    } catch (_) {
      // Ignored
    } finally {
      _tcpSocket = null;
      _udpSocket = null;
      _targetAddress = null;
      _targetPort = null;
      _protocol = null;
    }
  }
}
