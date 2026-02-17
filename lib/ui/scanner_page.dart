import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../models/scan_result.dart';
import '../services/audio_scanner_service.dart';
import '../services/logging_service.dart';
import '../services/settings_provider.dart';
import 'widgets/result_list_item.dart';
import 'widgets/scan_result_details.dart';

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  final AudioScannerService _scanner = AudioScannerService();
  final List<ScanResult> _results = [];
  bool _isScanning = false;
  bool _showOnlyProblematic = false;
  bool _isDragging = false;
  String _statusText = 'Ready to scan';
  double _progress = 0.0;
  int _totalFiles = 0;
  int _scannedFiles = 0;
  ScanResult? _selectedResult;
  
  // File-level progress tracking
  String _currentFileName = '';
  String _currentPhase = '';
  double _fileProgress = 0.0;
  int _segmentsCurrent = 0;
  int _segmentsTotal = 0;
  Duration? _currentFileDuration;

  List<ScanResult> get _filteredResults {
    if (_showOnlyProblematic) {
      return _results.where((r) => !r.isOk).toList();
    }
    return _results;
  }

  @override
  void initState() {
    super.initState();
    _initializeScanner();
  }

  Future<void> _initializeScanner() async {
    final settings = context.read<SettingsProvider>();
    final logger = context.read<LoggingService>();
    
    // Set custom FFmpeg paths if configured
    if (settings.ffmpegPath != null || settings.ffprobePath != null) {
      _scanner.setFfmpegPaths(
        ffmpegPath: settings.ffmpegPath,
        ffprobePath: settings.ffprobePath,
      );
    }

    // Check FFmpeg availability
    var available = await _scanner.checkFfmpegAvailable();
    
    // If not available, try to auto-detect from common locations
    if (!available) {
      final detectedPaths = await _detectFfmpegPaths();
      if (detectedPaths != null) {
        _scanner.setFfmpegPaths(
          ffmpegPath: detectedPaths['ffmpeg'],
          ffprobePath: detectedPaths['ffprobe'],
        );
        settings.ffmpegPath = detectedPaths['ffmpeg'];
        settings.ffprobePath = detectedPaths['ffprobe'];
        available = await _scanner.checkFfmpegAvailable();
        if (available) {
          logger.info('Auto-detected FFmpeg at: ${detectedPaths['ffmpeg']}');
        }
      }
    }
    
    if (!available && mounted) {
      setState(() {
        _statusText = 'FFmpeg not found. Please configure paths in Settings.';
      });
    } else if (mounted) {
      final version = await _scanner.getFfmpegVersion();
      logger.info('FFmpeg ready: ${version ?? 'unknown version'}');
    }
  }

  /// Try to detect FFmpeg from common installation locations
  Future<Map<String, String>?> _detectFfmpegPaths() async {
    // Common locations to check on Windows
    final homeDir = Platform.environment['USERPROFILE'] ?? '';
    final possiblePaths = [
      // User's Downloads folder (common for manual downloads)
      p.join(homeDir, 'Downloads'),
      // Common installation paths
      r'C:\ffmpeg\bin',
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

  Future<void> _pickFolder() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select audiobook folder',
    );

    if (result != null) {
      await _startScan(result);
    }
  }

  Future<void> _startScan(String path) async {
    if (_isScanning) return;

    final logger = context.read<LoggingService>();
    final settings = context.read<SettingsProvider>();

    // Update scanner settings
    _scanner.silenceThresholdDb = settings.silenceThresholdDb;
    _scanner.silenceDurationSec = settings.silenceDurationSec;
    _scanner.detectChapterSilence = settings.detectChapterSilence;

    setState(() {
      _isScanning = true;
      _results.clear();
      _statusText = 'Finding audio files...';
      _progress = 0.0;
      _selectedResult = null;
    });

    logger.info('Starting scan of: $path');

    try {
      // Find all audio files
      List<String> files;
      if (await FileSystemEntity.isDirectory(path)) {
        files = await _scanner.findAudioFiles(path);
      } else {
        files = [path];
      }

      if (files.isEmpty) {
        setState(() {
          _statusText = 'No audio files found';
          _isScanning = false;
        });
        logger.warning('No audio files found in: $path');
        return;
      }

      setState(() {
        _totalFiles = files.length;
        _scannedFiles = 0;
        _statusText = 'Scanning ${files.length} files...';
        _currentFileName = '';
        _currentPhase = '';
        _fileProgress = 0.0;
      });

      logger.info('Found ${files.length} audio files');

      // Get scan mode from settings
      final settings = context.read<SettingsProvider>();
      final scanMode = settings.scanMode;

      // Scan files with real-time progress
      await for (final progress in _scanner.scanFilesWithProgress(files, scanMode: scanMode)) {
        if (!mounted) return;
        
        if (progress.isFileProgressUpdate) {
          // Update file-level progress
          final fp = progress.fileProgress!;
          setState(() {
            _currentFileName = fp.fileName;
            _currentPhase = fp.phaseDescription;
            _fileProgress = fp.phaseProgress;
            _segmentsCurrent = fp.segmentsCurrent ?? 0;
            _segmentsTotal = fp.segmentsTotal ?? 0;
            _currentFileDuration = fp.fileDuration;
            _statusText = 'Scanning: ${fp.fileName}';
          });
        } else if (progress.result != null) {
          // File completed
          setState(() {
            _results.add(progress.result!);
            _scannedFiles = progress.current;
            _progress = progress.percentage;
            _currentFileName = '';
            _currentPhase = '';
            _fileProgress = 0.0;
          });

          // Log issues
          if (!progress.result!.isOk) {
            logger.warning('Issue found: ${progress.result!.path} - ${progress.result!.statusDescription}');
          }
        }
      }

      // Summary
      final problemCount = _results.where((r) => !r.isOk).length;
      setState(() {
        _statusText = 'Scan complete: ${_results.length} files, $problemCount issues';
        _isScanning = false;
        _currentFileName = '';
        _currentPhase = '';
      });

      logger.info('Scan complete: ${_results.length} files scanned, $problemCount issues found');
    } catch (e, st) {
      logger.error('Scan failed', e, st);
      setState(() {
        _statusText = 'Scan failed: $e';
        _isScanning = false;
      });
    }
  }

  Future<void> _handleDrop(List<String> paths) async {
    if (_isScanning || paths.isEmpty) return;

    // If single path, scan it
    if (paths.length == 1) {
      await _startScan(paths.first);
    } else {
      // Multiple files - scan each
      final logger = context.read<LoggingService>();
      final settings = context.read<SettingsProvider>();

      _scanner.silenceThresholdDb = settings.silenceThresholdDb;
      _scanner.silenceDurationSec = settings.silenceDurationSec;
      _scanner.detectChapterSilence = settings.detectChapterSilence;

      setState(() {
        _isScanning = true;
        _results.clear();
        _totalFiles = paths.length;
        _scannedFiles = 0;
        _progress = 0.0;
        _selectedResult = null;
        _currentFileName = '';
        _currentPhase = '';
        _fileProgress = 0.0;
      });

      logger.info('Starting scan of ${paths.length} dropped items');

      await for (final progress in _scanner.scanFilesWithProgress(paths, scanMode: settings.scanMode)) {
        if (!mounted) return;

        if (progress.isFileProgressUpdate) {
          final fp = progress.fileProgress!;
          setState(() {
            _currentFileName = fp.fileName;
            _currentPhase = fp.phaseDescription;
            _fileProgress = fp.phaseProgress;
            _segmentsCurrent = fp.segmentsCurrent ?? 0;
            _segmentsTotal = fp.segmentsTotal ?? 0;
            _currentFileDuration = fp.fileDuration;
            _statusText = 'Scanning: ${fp.fileName}';
          });
        } else if (progress.result != null) {
          setState(() {
            _results.add(progress.result!);
            _scannedFiles = progress.current;
            _progress = progress.percentage;
            _currentFileName = '';
            _currentPhase = '';
            _fileProgress = 0.0;
          });
        }
      }

      final problemCount = _results.where((r) => !r.isOk).length;
      setState(() {
        _statusText = 'Scan complete: ${_results.length} files, $problemCount issues';
        _isScanning = false;
        _currentFileName = '';
        _currentPhase = '';
      });

      logger.info('Scan complete: ${_results.length} files scanned, $problemCount issues found');
    }
  }

  Future<void> _exportReport() async {
    if (_results.isEmpty) return;

    final outputPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Export Report',
      fileName: 'audiobook_scan_report',
      type: FileType.custom,
      allowedExtensions: ['json', 'csv'],
    );

    if (outputPath == null) return;

    final logger = context.read<LoggingService>();

    try {
      final ext = p.extension(outputPath).toLowerCase();
      
      if (ext == '.csv') {
        // Export as CSV
        final rows = [
          ScanResult.csvHeaders(),
          ..._results.map((r) => r.toCsvRow()),
        ];
        final csv = const ListToCsvConverter().convert(rows);
        await File(outputPath).writeAsString(csv);
      } else {
        // Export as JSON
        final jsonPath = outputPath.endsWith('.json') ? outputPath : '$outputPath.json';
        final json = jsonEncode(_results.map((r) => r.toJson()).toList());
        await File(jsonPath).writeAsString(json);
      }

      logger.info('Report exported to: $outputPath');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Report exported to: $outputPath')),
        );
      }
    } catch (e) {
      logger.error('Failed to export report', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  Future<void> _reencodeSelected() async {
    if (_selectedResult == null) return;

    final settings = context.read<SettingsProvider>();
    final logger = context.read<LoggingService>();

    logger.info('Re-encoding: ${_selectedResult!.path}');

    final outputPath = await _scanner.reencodeFile(
      _selectedResult!.path,
      codec: settings.codec,
      bitrate: settings.bitrate,
    );

    if (outputPath != null) {
      logger.info('Re-encoded to: $outputPath');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Re-encoded to: $outputPath')),
        );
      }
    } else {
      logger.error('Re-encoding failed for: ${_selectedResult!.path}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Re-encoding failed')),
        );
      }
    }
  }

  Future<void> _deleteSelected() async {
    if (_selectedResult == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: Text('Are you sure you want to delete:\n${_selectedResult!.path}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final logger = context.read<LoggingService>();
    logger.info('Deleting: ${_selectedResult!.path}');

    final success = await _scanner.deleteFile(_selectedResult!.path, confirmed: true);
    
    if (success) {
      logger.info('Deleted: ${_selectedResult!.path}');
      setState(() {
        _results.remove(_selectedResult);
        _selectedResult = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File deleted')),
        );
      }
    } else {
      logger.error('Delete failed for: ${_selectedResult!.path}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Delete failed')),
        );
      }
    }
  }

  Future<void> _moveSelected() async {
    if (_selectedResult == null) return;

    final destDir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select destination folder',
    );

    if (destDir == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Move'),
        content: Text('Move file to:\n$destDir?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Move'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final logger = context.read<LoggingService>();
    logger.info('Moving: ${_selectedResult!.path} to $destDir');

    final newPath = await _scanner.moveFile(_selectedResult!.path, destDir, confirmed: true);
    
    if (newPath != null) {
      logger.info('Moved to: $newPath');
      setState(() {
        _results.remove(_selectedResult);
        _selectedResult = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('File moved to: $newPath')),
        );
      }
    } else {
      logger.error('Move failed for: ${_selectedResult!.path}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Move failed')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DropTarget(
      onDragEntered: (_) => setState(() => _isDragging = true),
      onDragExited: (_) => setState(() => _isDragging = false),
      onDragDone: (details) {
        setState(() => _isDragging = false);
        final paths = details.files.map((f) => f.path).toList();
        _handleDrop(paths);
      },
      child: Container(
        decoration: _isDragging
            ? BoxDecoration(
                border: Border.all(
                  color: colorScheme.primary,
                  width: 3,
                ),
              )
            : null,
        child: Column(
          children: [
            // Toolbar
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                border: Border(
                  bottom: BorderSide(color: colorScheme.outline.withAlpha(50)),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Buttons row
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: _isScanning ? null : _pickFolder,
                        icon: const Icon(Icons.folder_open),
                        label: const Text('Select Folder'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _results.isEmpty ? null : _exportReport,
                        icon: const Icon(Icons.download),
                        label: const Text('Export'),
                      ),
                      const Spacer(),
                      if (_selectedResult != null && !_selectedResult!.isOk) ...[
                        OutlinedButton.icon(
                          onPressed: _reencodeSelected,
                          icon: const Icon(Icons.autorenew),
                          label: const Text('Re-encode'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: _moveSelected,
                          icon: const Icon(Icons.drive_file_move),
                          label: const Text('Move'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: _deleteSelected,
                          icon: const Icon(Icons.delete),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: colorScheme.error,
                          ),
                          label: const Text('Delete'),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Progress and status
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_statusText),
                            if (_isScanning) ...[
                              const SizedBox(height: 8),
                              // Overall file progress
                              Row(
                                children: [
                                  Expanded(
                                    child: LinearProgressIndicator(value: _progress),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    '$_scannedFiles / $_totalFiles files',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                              // Current file progress details
                              if (_currentFileName.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(Icons.audio_file, size: 16),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              _currentFileName,
                                              style: theme.textTheme.bodyMedium?.copyWith(
                                                fontWeight: FontWeight.bold,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (_currentFileDuration != null)
                                            Text(
                                              _formatDuration(_currentFileDuration!),
                                              style: theme.textTheme.bodySmall,
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              value: _fileProgress > 0 ? _fileProgress : null,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              _currentPhase,
                                              style: theme.textTheme.bodySmall,
                                            ),
                                          ),
                                          if (_segmentsTotal > 1)
                                            Text(
                                              '$_segmentsCurrent / $_segmentsTotal',
                                              style: theme.textTheme.bodySmall?.copyWith(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                        ],
                                      ),
                                      if (_segmentsTotal > 1) ...[
                                        const SizedBox(height: 4),
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(4),
                                          child: LinearProgressIndicator(
                                            value: _fileProgress,
                                            backgroundColor: colorScheme.surfaceContainerLow,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Row(
                        children: [
                          Checkbox(
                            value: _showOnlyProblematic,
                            onChanged: (value) {
                              setState(() {
                                _showOnlyProblematic = value ?? false;
                              });
                            },
                          ),
                          const Text('Show only problematic'),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Results
            Expanded(
              child: _results.isEmpty
                  ? _buildEmptyState()
                  : Row(
                      children: [
                        // Results list
                        Expanded(
                          flex: 2,
                          child: ListView.builder(
                            itemCount: _filteredResults.length,
                            itemBuilder: (context, index) {
                              final result = _filteredResults[index];
                              return ResultListItem(
                                result: result,
                                isSelected: _selectedResult == result,
                                onTap: () {
                                  setState(() {
                                    _selectedResult = result;
                                  });
                                },
                              );
                            },
                          ),
                        ),
                        // Details panel
                        if (_selectedResult != null)
                          Container(
                            width: 400,
                            decoration: BoxDecoration(
                              border: Border(
                                left: BorderSide(
                                  color: colorScheme.outline.withAlpha(50),
                                ),
                              ),
                            ),
                            child: ScanResultDetails(result: _selectedResult!),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.audio_file,
            size: 80,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'Drop folders or files here',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Or click "Select Folder" to browse',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Supported: MP3, M4B, M4A, AAC, WAV, FLAC, OGG',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ],
      ),
    );
  }
}
