import 'package:flutter/material.dart';
import '../../domain/entities/connection_status.dart';
import '../../domain/entities/stream_config.dart';
import 'package:camext/core/theme/app_theme.dart';
import '../cubit/stream_notifier.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:typed_data';
import 'package:camext/features/stream/data/datasources/platform_channel_source.dart';

class DashboardPage extends StatefulWidget {
  final StreamNotifier notifier;

  const DashboardPage({super.key, required this.notifier});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final _ipController = TextEditingController();
  final _portController = TextEditingController();

  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _isCameraInitialized = false;
  bool _isProcessingFrame = false;
  String _cameraError = '';

  @override
  void initState() {
    super.initState();
    _ipController.text = widget.notifier.value.config.ipAddress;
    _portController.text = widget.notifier.value.config.port.toString();
    
    // Inisialisasi kamera & minta izin
    _initCamera();

    // Dengar status koneksi untuk menyalakan/mematikan stream kamera
    widget.notifier.addListener(_onStreamStateChanged);
  }

  Future<void> _initCamera() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      setState(() {
        _cameraError = 'Izin kamera ditolak. Silakan berikan izin di pengaturan.';
      });
      return;
    }

    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() {
          _cameraError = 'Kamera fisik tidak ditemukan pada HP ini.';
        });
        return;
      }

      // Pilih kamera belakang default
      final camera = _cameras.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );

      // Dispose controller lama jika ada untuk menghindari memory leaks
      if (_cameraController != null) {
        _isCameraInitialized = false;
        await _cameraController!.dispose();
        _cameraController = null;
      }

      ResolutionPreset preset = ResolutionPreset.high; // default 720p
      final width = widget.notifier.value.config.width;
      if (width == 1920) {
        preset = ResolutionPreset.veryHigh;
      } else if (width == 1280) {
        preset = ResolutionPreset.high;
      } else if (width == 640) {
        preset = ResolutionPreset.medium;
      }

      _cameraController = CameraController(
        camera,
        preset,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _cameraController!.initialize();
      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
      }

      // Jika sudah terhubung, langsung streaming
      if (widget.notifier.value.status == ConnectionStatus.connected) {
        _startImageStreaming();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _cameraError = 'Gagal inisialisasi kamera: $e';
        });
      }
    }
  }

  void _onStreamStateChanged() {
    final status = widget.notifier.value.status;
    if (status == ConnectionStatus.connected) {
      _startImageStreaming();
    } else if (status == ConnectionStatus.disconnected || status == ConnectionStatus.failed) {
      _stopImageStreaming();
    }
  }

  void _startImageStreaming() {
    if (_cameraController == null || !_isCameraInitialized) return;
    if (_cameraController!.value.isStreamingImages) return;

    _isProcessingFrame = false;
    _cameraController!.startImageStream((CameraImage image) async {
      if (_isProcessingFrame) return;
      _isProcessingFrame = true;

      try {
        final planeY = image.planes[0].bytes;
        final planeU = image.planes[1].bytes;
        final planeV = image.planes[2].bytes;

        // Dapatkan sensor orientation agar rotasi gambar tegak lurus sempurna
        final sensorOrientation = _cameraController!.description.sensorOrientation;

        final jpegBytes = await PlatformChannelSource().yuvToJpeg(
          y: planeY,
          u: planeU,
          v: planeV,
          yRowStride: image.planes[0].bytesPerRow,
          uRowStride: image.planes[1].bytesPerRow,
          vRowStride: image.planes[2].bytesPerRow,
          uPixelStride: image.planes[1].bytesPerPixel ?? 1,
          vPixelStride: image.planes[2].bytesPerPixel ?? 1,
          width: image.width,
          height: image.height,
          quality: 75,
          rotation: sensorOrientation,
        );

        PlatformChannelSource().injectFrame(jpegBytes);
      } catch (e) {
        debugPrint('Frame conversion error: $e');
      } finally {
        _isProcessingFrame = false;
      }
    });
  }

  void _stopImageStreaming() {
    if (_cameraController == null || !_isCameraInitialized) return;
    if (!_cameraController!.value.isStreamingImages) return;
    try {
      _cameraController!.stopImageStream();
    } catch (e) {
      debugPrint('Error stopping image stream: $e');
    }
  }

  @override
  void dispose() {
    widget.notifier.removeListener(_onStreamStateChanged);
    _cameraController?.dispose();
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ValueListenableBuilder<StreamState>(
        valueListenable: widget.notifier,
        builder: (context, state, child) {
          final isStreaming = state.status == ConnectionStatus.connected;
          final isConnecting = state.status == ConnectionStatus.connecting;

          return Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppTheme.darkBg, Color(0xFF141724)],
              ),
            ),
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    _buildHeader(),
                    const SizedBox(height: 24),

                    // Camera Preview
                    _buildCameraPreview(),
                    const SizedBox(height: 24),

                    // Status Indicator Glow Card
                    _buildStatusCard(state),
                    const SizedBox(height: 32),

                    // Statistics Cards Grid
                    if (isStreaming) ...[
                      _buildStatsGrid(state),
                      const SizedBox(height: 32),
                    ],

                    // Configuration Form Card
                    _buildConfigCard(state, isStreaming || isConnecting),
                    const SizedBox(height: 32),

                    // Stream Action Button
                    _buildActionButton(state, isStreaming, isConnecting),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCameraPreview() {
    return Container(
      height: 240,
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.borderGlow, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppTheme.accentNeonCyan.withOpacity(0.05),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_isCameraInitialized && _cameraController != null)
            CameraPreview(_cameraController!)
          else if (_cameraError.isNotEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _cameraError,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            const Center(
              child: CircularProgressIndicator(color: AppTheme.accentNeonCyan),
            ),
          
          // Gradient Overlay
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.3),
                    Colors.transparent,
                    Colors.black.withOpacity(0.5),
                  ],
                ),
              ),
            ),
          ),

          // Label
          Positioned(
            left: 16,
            bottom: 16,
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: widget.notifier.value.status == ConnectionStatus.connected 
                        ? AppTheme.accentNeonGreen 
                        : Colors.amber,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: (widget.notifier.value.status == ConnectionStatus.connected 
                            ? AppTheme.accentNeonGreen 
                            : Colors.amber).withOpacity(0.5),
                        blurRadius: 6,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  widget.notifier.value.status == ConnectionStatus.connected
                      ? 'LIVE STREAMING'
                      : 'KAMERA SIAP',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.accentNeonCyan.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.accentNeonCyan.withOpacity(0.3)),
          ),
          child: const Icon(
            Icons.videocam_rounded,
            color: AppTheme.accentNeonCyan,
            size: 28,
          ),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'CamExt Klien',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
                color: AppTheme.textMain,
              ),
            ),
            Text(
              'Alternatif DroidCam Rendah Latensi',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textMuted,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatusCard(StreamState state) {
    Color glowColor;
    String statusText;
    IconData icon;

    switch (state.status) {
      case ConnectionStatus.connected:
        glowColor = AppTheme.accentNeonGreen;
        statusText = 'SEDANG BERJALAN';
        icon = Icons.online_prediction_rounded;
        break;
      case ConnectionStatus.connecting:
        glowColor = AppTheme.accentNeonCyan;
        statusText = 'MENGHUBUNGKAN';
        icon = Icons.sync_rounded;
        break;
      case ConnectionStatus.failed:
        glowColor = Colors.redAccent;
        statusText = 'KONEKSI GAGAL';
        icon = Icons.error_outline_rounded;
        break;
      case ConnectionStatus.disconnected:
      default:
        glowColor = AppTheme.textMuted;
        statusText = 'SIAP DIGUNAKAN';
        icon = Icons.power_settings_new_rounded;
        break;
    }

    return Card(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [AppTheme.cardBg, AppTheme.cardBg.withOpacity(0.8)],
          ),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: glowColor.withOpacity(0.4),
                        blurRadius: 16,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: Icon(icon, color: glowColor, size: 36),
                ),
                const SizedBox(width: 16),
                Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: glowColor,
                    letterSpacing: 2.0,
                  ),
                ),
              ],
            ),
            if (state.errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(
                state.errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 12,
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildStatsGrid(StreamState state) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: 1.5,
      children: [
        _buildStatItem(
          'Laju Frame (FPS)',
          state.stats.currentFps.toStringAsFixed(1),
          Icons.speed_rounded,
          AppTheme.accentNeonGreen,
        ),
        _buildStatItem(
          'Throughput (Mbps)',
          state.stats.dataRateMbps.toStringAsFixed(2),
          Icons.network_check_rounded,
          AppTheme.accentNeonCyan,
        ),
      ],
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                ),
                Icon(icon, color: color, size: 18),
              ],
            ),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 26,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigCard(StreamState state, bool isDisabled) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'PENGATURAN KONEKSI',
              style: TextStyle(
                color: AppTheme.textMain,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),

            // IP Address Input
            TextField(
              controller: _ipController,
              enabled: !isDisabled,
              keyboardType: TextInputType.values[0], // text/numbers
              decoration: const InputDecoration(
                labelText: 'IP Address OBS Studio',
                hintText: '192.168.1.xxx',
                prefixIcon: Icon(Icons.laptop_rounded, color: AppTheme.accentNeonCyan),
              ),
              onChanged: widget.notifier.updateIpAddress,
            ),
            const SizedBox(height: 16),

            // Port Input
            TextField(
              controller: _portController,
              enabled: !isDisabled,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Port Soket',
                hintText: '4455',
                prefixIcon: Icon(Icons.settings_ethernet_rounded, color: AppTheme.accentNeonCyan),
              ),
              onChanged: (val) {
                final port = int.tryParse(val) ?? 4455;
                widget.notifier.updatePort(port);
              },
            ),
            const SizedBox(height: 24),

            // Protocol Selection
            Row(
              children: [
                Expanded(
                  child: _buildSelectorTile<ConnectionProtocol>(
                    title: 'TCP (Stabil)',
                    value: ConnectionProtocol.tcp,
                    groupValue: state.config.protocol,
                    isDisabled: isDisabled,
                    onChanged: (p) => widget.notifier.updateProtocol(p!),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSelectorTile<ConnectionProtocol>(
                    title: 'UDP (Cepat)',
                    value: ConnectionProtocol.udp,
                    groupValue: state.config.protocol,
                    isDisabled: isDisabled,
                    onChanged: (p) => widget.notifier.updateProtocol(p!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Camera Resolution Selection
            const Text(
              'RESOLUSI KAMERA (MEMPENGARUHI FPS & LATENSI)',
              style: TextStyle(
                color: AppTheme.textMuted,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildSelectorTile<int>(
                    title: '1080p (HQ)',
                    value: 1920,
                    groupValue: state.config.width,
                    isDisabled: isDisabled,
                    onChanged: (val) {
                      widget.notifier.updateResolution(1920, 1080);
                      _initCamera();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildSelectorTile<int>(
                    title: '720p (Seimbang)',
                    value: 1280,
                    groupValue: state.config.width,
                    isDisabled: isDisabled,
                    onChanged: (val) {
                      widget.notifier.updateResolution(1280, 720);
                      _initCamera();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildSelectorTile<int>(
                    title: '480p (Lancar)',
                    value: 640,
                    groupValue: state.config.width,
                    isDisabled: isDisabled,
                    onChanged: (val) {
                      widget.notifier.updateResolution(640, 480);
                      _initCamera();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Codec Selection
            const Text(
              'PILIHAN CODEC VIDEO',
              style: TextStyle(
                color: AppTheme.textMuted,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildSelectorTile<VideoCodec>(
                    title: 'H.264',
                    value: VideoCodec.h264,
                    groupValue: state.config.codec,
                    isDisabled: isDisabled,
                    onChanged: (c) => widget.notifier.updateCodec(c!),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildSelectorTile<VideoCodec>(
                    title: 'H.265',
                    value: VideoCodec.h265,
                    groupValue: state.config.codec,
                    isDisabled: isDisabled,
                    onChanged: (c) => widget.notifier.updateCodec(c!),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildSelectorTile<VideoCodec>(
                    title: 'MJPEG',
                    value: VideoCodec.mjpeg,
                    groupValue: state.config.codec,
                    isDisabled: isDisabled,
                    onChanged: (c) => widget.notifier.updateCodec(c!),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectorTile<T>({
    required String title,
    required T value,
    required T groupValue,
    required bool isDisabled,
    required ValueChanged<T?> onChanged,
  }) {
    final isSelected = value == groupValue;
    return Opacity(
      opacity: isDisabled ? 0.5 : 1.0,
      child: InkWell(
        onTap: isDisabled ? null : () => onChanged(value),
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.accentNeonCyan.withOpacity(0.1)
                : AppTheme.cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppTheme.accentNeonCyan : AppTheme.borderGlow,
              width: 1.5,
            ),
          ),
          child: Center(
            child: Text(
              title,
              style: TextStyle(
                color: isSelected ? AppTheme.accentNeonCyan : AppTheme.textMuted,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(StreamState state, bool isStreaming, bool isConnecting) {
    final buttonColor = isStreaming ? Colors.redAccent : AppTheme.accentNeonCyan;
    final text = isStreaming
        ? 'BERHENTI STREAMING'
        : (isConnecting ? 'MENGHUBUNGKAN...' : 'MULAI STREAMING');

    return Container(
      height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: buttonColor.withOpacity(0.3),
            blurRadius: 12,
            spreadRadius: 2,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: buttonColor,
          foregroundColor: isStreaming ? Colors.white : AppTheme.darkBg,
        ),
        onPressed: isConnecting
            ? null
            : () {
                if (isStreaming) {
                  widget.notifier.stopStreaming();
                } else {
                  widget.notifier.startStreaming();
                }
              },
        child: Text(text),
      ),
    );
  }
}
