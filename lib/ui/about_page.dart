import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../models/scan_result.dart';
import '../services/audio_scanner_service.dart';
import '../services/logging_service.dart';
import '../services/settings_provider.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  final AudioScannerService _scanner = AudioScannerService();
  String? _ffmpegVersion;
  bool _ffmpegAvailable = false;
  bool _isRunningTest = false;
  ScanResult? _testResult;
  String? _testStatus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkFfmpeg();
    });
  }

  Future<void> _checkFfmpeg() async {
    // Use configured FFmpeg paths from settings
    final settings = context.read<SettingsProvider>();
    if (settings.ffmpegPath != null || settings.ffprobePath != null) {
      _scanner.setFfmpegPaths(
        ffmpegPath: settings.ffmpegPath,
        ffprobePath: settings.ffprobePath,
      );
    }
    
    _ffmpegAvailable = await _scanner.checkFfmpegAvailable();
    if (_ffmpegAvailable) {
      _ffmpegVersion = await _scanner.getFfmpegVersion();
    }
    if (mounted) setState(() {});
  }

  /// Run a sanity test by generating a test file with silence and scanning it
  Future<void> _runSanityTest() async {
    final settings = context.read<SettingsProvider>();
    final logger = context.read<LoggingService>();

    setState(() {
      _isRunningTest = true;
      _testResult = null;
      _testStatus = 'Creating test file with silence...';
    });

    try {
      // Get temp directory for test file
      final tempDir = await getTemporaryDirectory();
      final testDir = Directory(p.join(tempDir.path, 'audiobook_validator', 'test'));
      await testDir.create(recursive: true);
      final testFilePath = p.join(testDir.path, 'sanity_test.m4a');

      // Get FFmpeg path
      final ffmpegPath = settings.ffmpegPath ?? 'ffmpeg';

      // Create test file: 3s tone + 15s silence + 3s tone
      // The 15s silence should trigger the default 10s threshold
      logger.info('Sanity test: Creating test audio file');
      
      final result = await Process.run(
        ffmpegPath,
        [
          '-y',
          '-f', 'lavfi', '-i', 'sine=frequency=440:duration=3',
          '-f', 'lavfi', '-i', 'anullsrc=r=44100:cl=stereo',
          '-f', 'lavfi', '-i', 'sine=frequency=880:duration=3',
          '-filter_complex', '[0:a][1:a][2:a]concat=n=3:v=0:a=1[out]',
          '-map', '[out]',
          '-t', '21',
          '-c:a', 'aac',
          '-b:a', '128k',
          testFilePath,
        ],
      );

      if (result.exitCode != 0) {
        throw Exception('FFmpeg failed to create test file: ${result.stderr}');
      }

      // Verify file was created
      if (!await File(testFilePath).exists()) {
        throw Exception('Test file was not created');
      }

      setState(() {
        _testStatus = 'Scanning test file for silence...';
      });

      // Configure scanner with current settings
      _scanner.setFfmpegPaths(
        ffmpegPath: settings.ffmpegPath,
        ffprobePath: settings.ffprobePath,
      );
      _scanner.silenceThresholdDb = settings.silenceThresholdDb;
      _scanner.silenceDurationSec = settings.silenceDurationSec;

      // Scan the test file
      logger.info('Sanity test: Scanning test file');
      final scanResult = await _scanner.scanFile(testFilePath);

      // Clean up test file
      try {
        await File(testFilePath).delete();
      } catch (_) {}

      setState(() {
        _testResult = scanResult;
        _isRunningTest = false;
        
        if (scanResult.hasLongSilence) {
          _testStatus = '✓ PASS: Silence detection working!';
          logger.info('Sanity test PASSED: Detected ${scanResult.silenceIntervals.length} silence interval(s)');
        } else {
          _testStatus = '✗ FAIL: Silence not detected (check threshold settings)';
          logger.warning('Sanity test FAILED: No silence detected');
        }
      });
    } catch (e, st) {
      logger.error('Sanity test failed', e, st);
      setState(() {
        _isRunningTest = false;
        _testStatus = '✗ ERROR: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 40),
              
              // App icon
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.audiotrack,
                  size: 64,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 24),

              // App name
              Text(
                'Audiobook Validator',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Version 1.0.0',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: colorScheme.outline,
                ),
              ),
              const SizedBox(height: 32),

              // Description
              Text(
                'A powerful tool for validating audiobook files. '
                'Detect missing audio streams, file corruption, '
                'long silences, and chapter-level issues.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 32),

              // System info card
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: colorScheme.outline.withAlpha(50)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'System Information',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      _buildInfoRow(
                        'Platform',
                        '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
                        Icons.computer,
                      ),
                      _buildInfoRow(
                        'Dart',
                        Platform.version.split(' ').first,
                        Icons.code,
                      ),
                      const Divider(height: 24),
                      _buildInfoRow(
                        'FFmpeg',
                        _ffmpegAvailable
                            ? 'Available'
                            : 'Not found',
                        Icons.movie,
                        statusColor: _ffmpegAvailable ? Colors.green : Colors.red,
                      ),
                      if (_ffmpegVersion != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 32, top: 4),
                          child: Text(
                            _ffmpegVersion!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.outline,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Sanity Test card
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: colorScheme.outline.withAlpha(50)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.science, color: colorScheme.primary),
                          const SizedBox(width: 8),
                          Text(
                            'Sanity Test',
                            style: theme.textTheme.titleMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Generate a test audio file with 15 seconds of silence '
                        'and verify that the silence detection is working correctly.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.outline,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_isRunningTest)
                        Row(
                          children: [
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _testStatus ?? 'Running test...',
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        )
                      else ...[
                        FilledButton.icon(
                          onPressed: _ffmpegAvailable ? _runSanityTest : null,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Run Silence Detection Test'),
                        ),
                        if (_testStatus != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _testStatus!.startsWith('✓')
                                  ? Colors.green.withAlpha(30)
                                  : Colors.red.withAlpha(30),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _testStatus!.startsWith('✓')
                                      ? Icons.check_circle
                                      : Icons.error,
                                  color: _testStatus!.startsWith('✓')
                                      ? Colors.green
                                      : Colors.red,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _testStatus!,
                                    style: TextStyle(
                                      color: _testStatus!.startsWith('✓')
                                          ? Colors.green.shade700
                                          : Colors.red.shade700,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (_testResult != null && _testResult!.silenceIntervals.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Detected ${_testResult!.silenceIntervals.length} silence interval(s):',
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 4),
                          ...(_testResult!.silenceIntervals.take(3).map((s) => Text(
                                '  • ${s.toString()}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontFamily: 'monospace',
                                  color: colorScheme.outline,
                                ),
                              ))),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Features card
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: colorScheme.outline.withAlpha(50)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Features',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      _buildFeatureItem(
                        Icons.folder_open,
                        'Folder & Drag-and-Drop',
                        'Scan folders or drop files directly',
                      ),
                      _buildFeatureItem(
                        Icons.search,
                        'Audio Stream Detection',
                        'Verify audio streams exist using ffprobe',
                      ),
                      _buildFeatureItem(
                        Icons.broken_image,
                        'Corruption Detection',
                        'Check for file corruption using ffmpeg',
                      ),
                      _buildFeatureItem(
                        Icons.volume_off,
                        'Silence Detection',
                        'Find long silent sections in audio',
                      ),
                      _buildFeatureItem(
                        Icons.bookmark,
                        'Chapter Analysis',
                        'Parse M4B chapters and detect chapter silence',
                      ),
                      _buildFeatureItem(
                        Icons.autorenew,
                        'Re-encoding',
                        'Convert problematic files to clean formats',
                      ),
                      _buildFeatureItem(
                        Icons.waves,
                        'Waveform Preview',
                        'Visual waveform generation for files',
                      ),
                      _buildFeatureItem(
                        Icons.download,
                        'Export Reports',
                        'Save scan results as JSON or CSV',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Supported formats
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: colorScheme.outline.withAlpha(50)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Supported Formats',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: AudioScannerService.supportedExtensions
                            .map((ext) => Chip(
                                  label: Text(ext.toUpperCase()),
                                  padding: EdgeInsets.zero,
                                  visualDensity: VisualDensity.compact,
                                ))
                            .toList(),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 40),

              // Footer
              Text(
                'Built with Flutter',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.outline,
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    String label,
    String value,
    IconData icon, {
    Color? statusColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.outline),
          const SizedBox(width: 12),
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: statusColor,
                    fontWeight: statusColor != null ? FontWeight.bold : null,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureItem(IconData icon, String title, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                ),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
