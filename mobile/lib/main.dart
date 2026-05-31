import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/theme/app_theme.dart';
import 'features/stream/data/datasources/platform_channel_source.dart';
import 'features/stream/data/datasources/socket_egress_source.dart';
import 'features/stream/data/repositories/stream_repository_impl.dart';
import 'features/stream/domain/usecases/get_connection_status.dart';
import 'features/stream/domain/usecases/get_stream_stats.dart';
import 'features/stream/domain/usecases/start_stream.dart';
import 'features/stream/domain/usecases/stop_stream.dart';
import 'features/stream/presentation/cubit/stream_notifier.dart';
import 'features/stream/presentation/pages/dashboard_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Kunci orientasi ke Portrait saja untuk kestabilan UI
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Pengaturan warna status bar agar menyatu dengan latar belakang gelap
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  // --- COMPOSITION ROOT (DEPENDENCY INJECTION) ---
  
  // 1. Data Sources
  final platformSource = PlatformChannelSource();
  final socketSource = SocketEgressSource();

  // 2. Repository Implementation
  final streamRepository = StreamRepositoryImpl(
    platformSource: platformSource,
    socketSource: socketSource,
  );

  // 3. Use Cases
  final startStream = StartStreamUseCase(streamRepository);
  final stopStream = StopStreamUseCase(streamRepository);
  final getStreamStats = GetStreamStatsUseCase(streamRepository);
  final getConnectionStatus = GetConnectionStatusUseCase(streamRepository);

  // 4. State Notifier (ValueNotifier)
  final streamNotifier = StreamNotifier(
    startStreamUseCase: startStream,
    stopStreamUseCase: stopStream,
    getStreamStatsUseCase: getStreamStats,
    getConnectionStatusUseCase: getConnectionStatus,
  );

  runApp(CamExtApp(streamNotifier: streamNotifier));
}

class CamExtApp extends StatelessWidget {
  final StreamNotifier streamNotifier;

  const CamExtApp({super.key, required this.streamNotifier});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CamExt - Mobile Client',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: DashboardPage(notifier: streamNotifier),
    );
  }
}
