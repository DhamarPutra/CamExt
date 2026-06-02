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
  String _cameraError = '';
  List<Map<String, dynamic>> _supportedResolutions = [];

  @override
  void initState() {
    super.initState();
    _ipController.text = widget.notifier.value.config.ipAddress;
    _portController.text = widget.notifier.value.config.port.toString();
    
    _requestPermissions();
    _loadResolutions();
  }

  Future<void> _loadResolutions() async {
    final res = await PlatformChannelSource().getSupportedResolutions();
    setState(() {
      _supportedResolutions = res;
    });
    // Set the first available resolution as active config
    if (res.isNotEmpty) {
      final width = res.first['width'] as int;
      final height = res.first['height'] as int;
      final maxFps = res.first['maxFps'] as int;
      widget.notifier.updateResolutionAndFps(width, height, maxFps);
    }
  }

  Future<void> _requestPermissions() async {
    final cameraStatus = await Permission.camera.request();
    final micStatus = await Permission.microphone.request();
    if (!cameraStatus.isGranted || !micStatus.isGranted) {
      setState(() {
        _cameraError = 'Izin Kamera & Mikrofon diperlukan untuk streaming.';
      });
    }
  }

  @override
  void dispose() {
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
    final isStreaming = widget.notifier.value.status == ConnectionStatus.connected;
    return Container(
      height: 180,
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isStreaming ? AppTheme.accentNeonGreen : AppTheme.borderGlow, 
          width: 1.5
        ),
        boxShadow: [
          BoxShadow(
            color: (isStreaming ? AppTheme.accentNeonGreen : AppTheme.accentNeonCyan).withOpacity(0.05),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (isStreaming)
            const Center(
              child: SizedBox(
                width: 100,
                height: 100,
                child: CircularProgressIndicator(
                  color: AppTheme.accentNeonGreen,
                  strokeWidth: 2,
                ),
              ),
            ),
          
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isStreaming ? Icons.sensors_rounded : Icons.videocam_off_rounded,
                size: 48,
                color: isStreaming ? AppTheme.accentNeonGreen : AppTheme.textMuted,
              ),
              const SizedBox(height: 16),
              Text(
                isStreaming ? 'TRANSMISI LIVE AKTIF' : 'STREAMING NONAKTIF',
                style: TextStyle(
                  color: isStreaming ? AppTheme.accentNeonGreen : AppTheme.textMuted,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                isStreaming 
                    ? 'Kamera Belakang -> PC via USB/Wi-Fi' 
                    : 'Siap menghubungkan perangkat',
                style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 12,
                ),
              ),
            ],
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

            const SizedBox(height: 12),
            // Auto Mode Indicator Text
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1B1E2E),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF2C314C)),
              ),
              child: Row(
                children: [
                  Icon(
                    state.config.ipAddress == '127.0.0.1'
                        ? Icons.usb_rounded
                        : Icons.wifi_rounded,
                    color: AppTheme.accentNeonCyan,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      state.config.ipAddress == '127.0.0.1'
                          ? '🔌 Mode USB (ADB Reverse) aktif. Pastikan adb reverse tcp:4455 tcp:4455 telah berjalan di PC.'
                          : '📶 Mode Wireless (Wi-Fi) aktif. Pastikan HP dan PC berada dalam satu jaringan.',
                      style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

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
            if (_supportedResolutions.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accentNeonCyan),
                  ),
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _supportedResolutions.map((item) {
                  final w = item['width'] as int;
                  final h = item['height'] as int;
                  final maxFps = item['maxFps'] as int;
                  
                  final title = '${h}p (${maxFps} FPS)';
                  
                  return SizedBox(
                    width: (MediaQuery.of(context).size.width - 68) / 2, // 2 items per row
                    child: _buildSelectorTile<int>(
                      title: title,
                      value: w,
                      groupValue: state.config.width,
                      isDisabled: isDisabled,
                      onChanged: (val) {
                        widget.notifier.updateResolutionAndFps(w, h, maxFps);
                      },
                    ),
                  );
                }).toList(),
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
            const SizedBox(height: 24),
            const Divider(color: Color(0xFF2C314C)),
            const SizedBox(height: 12),

            // Microphone Streaming Toggle
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'STREAMING SUARA (MIKROFON)',
                        style: TextStyle(
                          color: AppTheme.textMuted,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Mengirimkan suara mikrofon HP ke PC secara real-time',
                        style: TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: state.config.enableAudio,
                  activeColor: AppTheme.accentNeonCyan,
                  onChanged: isDisabled
                      ? null
                      : (val) {
                          widget.notifier.toggleAudio(val);
                        },
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
