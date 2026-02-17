import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'services/audio_scanner_service.dart';
import 'services/logging_service.dart';
import 'services/settings_provider.dart';
import 'ui/scanner_page.dart';
import 'ui/settings_page.dart';
import 'ui/logs_page.dart';
import 'ui/about_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize services
  final settingsProvider = SettingsProvider();
  await settingsProvider.load();

  final loggingService = LoggingService();
  await loggingService.initialize();

  // Auto-detect FFmpeg if not configured
  if (settingsProvider.ffmpegPath == null) {
    final detectedPaths = await _detectFfmpegPaths();
    if (detectedPaths != null) {
      settingsProvider.ffmpegPath = detectedPaths['ffmpeg'];
      settingsProvider.ffprobePath = detectedPaths['ffprobe'];
      loggingService.info('Auto-detected FFmpeg at: ${detectedPaths['ffmpeg']}');
    }
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settingsProvider),
        ChangeNotifierProvider.value(value: loggingService),
      ],
      child: const AudiobookValidatorApp(),
    ),
  );
}

/// Try to detect FFmpeg from common installation locations
Future<Map<String, String>?> _detectFfmpegPaths() async {
  final scanner = AudioScannerService();
  
  // First check if FFmpeg is already in PATH
  if (await scanner.checkFfmpegAvailable()) {
    return null; // Already available via PATH
  }

  // Common locations to check on Windows
  final homeDir = Platform.environment['USERPROFILE'] ?? '';
  final possiblePaths = [
    // Standard installation path (top priority)
    r'C:\ffmpeg\bin',
    // User's Downloads folder (common for manual downloads)
    p.join(homeDir, 'Downloads'),
    // Other common installation paths
    r'C:\Program Files\ffmpeg\bin',
    r'C:\Program Files (x86)\ffmpeg\bin',
    // Chocolatey
    r'C:\ProgramData\chocolatey\bin',
    // Scoop
    p.join(homeDir, 'scoop', 'shims'),
  ];

  for (final basePath in possiblePaths) {
    final binPath = await _findFfmpegInDir(basePath);
    if (binPath != null) {
      final ffmpegPath = p.join(binPath, Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg');
      final ffprobePath = p.join(binPath, Platform.isWindows ? 'ffprobe.exe' : 'ffprobe');
      
      if (await File(ffmpegPath).exists() && await File(ffprobePath).exists()) {
        return {'ffmpeg': ffmpegPath, 'ffprobe': ffprobePath};
      }
    }
  }
  return null;
}

/// Recursively search for ffmpeg binary in a directory (max 2 levels deep)
Future<String?> _findFfmpegInDir(String dirPath) async {
  try {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return null;

    // Check direct path
    final ffmpegExe = Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg';
    if (await File(p.join(dirPath, ffmpegExe)).exists()) {
      return dirPath;
    }

    // Check subdirectories (for ffmpeg-*-build folders)
    await for (final entity in dir.list()) {
      if (entity is Directory) {
        final name = p.basename(entity.path).toLowerCase();
        if (name.contains('ffmpeg')) {
          // Check for bin subdirectory
          final binPath = p.join(entity.path, 'bin');
          if (await File(p.join(binPath, ffmpegExe)).exists()) {
            return binPath;
          }
          // Check the directory itself
          if (await File(p.join(entity.path, ffmpegExe)).exists()) {
            return entity.path;
          }
          // One more level (ffmpeg-xxx/ffmpeg-xxx/bin pattern)
          await for (final subEntity in entity.list()) {
            if (subEntity is Directory) {
              final subBinPath = p.join(subEntity.path, 'bin');
              if (await File(p.join(subBinPath, ffmpegExe)).exists()) {
                return subBinPath;
              }
            }
          }
        }
      }
    }
  } catch (e) {
    // Ignore errors during detection
  }
  return null;
}

class AudiobookValidatorApp extends StatelessWidget {
  const AudiobookValidatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return MaterialApp(
      title: 'Audiobook Validator',
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  // Use keys to preserve state across tab switches
  final GlobalKey<State> _scannerKey = GlobalKey();
  
  static const List<NavigationDestination> _destinations = [
    NavigationDestination(
      icon: Icon(Icons.search),
      selectedIcon: Icon(Icons.search),
      label: 'Scanner',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings),
      label: 'Settings',
    ),
    NavigationDestination(
      icon: Icon(Icons.article_outlined),
      selectedIcon: Icon(Icons.article),
      label: 'Logs',
    ),
    NavigationDestination(
      icon: Icon(Icons.info_outline),
      selectedIcon: Icon(Icons.info),
      label: 'About',
    ),
  ];

  // Build all pages once and keep them alive
  late final List<Widget> _pages = [
    ScannerPage(key: _scannerKey),
    const SettingsPage(),
    const LogsPage(),
    const AboutPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Row(
        children: [
          // Navigation rail for desktop
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) {
              setState(() {
                _selectedIndex = index;
              });
            },
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.audiotrack,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Audiobook\nValidator',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
            destinations: _destinations.map((dest) {
              return NavigationRailDestination(
                icon: dest.icon,
                selectedIcon: dest.selectedIcon,
                label: Text(dest.label),
              );
            }).toList(),
          ),
          // Divider
          VerticalDivider(
            thickness: 1,
            width: 1,
            color: colorScheme.outline.withAlpha(50),
          ),
          // Main content - IndexedStack preserves state across tab switches
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: _pages,
            ),
          ),
        ],
      ),
    );
  }
}
