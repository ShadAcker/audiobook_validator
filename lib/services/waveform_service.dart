import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Service for generating waveform visualizations using FFmpeg
class WaveformService {
  String _ffmpegPath = 'ffmpeg';
  Directory? _cacheDir;
  bool _initialized = false;

  /// Set custom FFmpeg path
  void setFfmpegPath(String path) {
    _ffmpegPath = path;
  }

  /// Initialize the waveform service
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      final tempDir = await getTemporaryDirectory();
      _cacheDir = Directory(p.join(tempDir.path, 'audiobook_validator', 'waveforms'));
      await _cacheDir!.create(recursive: true);
      _initialized = true;
    } catch (e) {
      // Failed to initialize
    }
  }

  /// Generate a waveform PNG for an audio file
  /// Returns the path to the generated PNG, or null on failure
  Future<String?> generateWaveform(
    String audioPath, {
    int width = 800,
    int height = 120,
    String? backgroundColor,
    String? waveColor,
  }) async {
    if (_cacheDir == null) {
      await initialize();
    }

    if (_cacheDir == null) return null;

    // Generate a unique filename based on the audio path
    final hash = audioPath.hashCode.toRadixString(16);
    final outputPath = p.join(_cacheDir!.path, 'waveform_$hash.png');

    // Check cache
    if (await File(outputPath).exists()) {
      return outputPath;
    }

    backgroundColor ??= '#1a1a2e';
    waveColor ??= '#0f3460|#e94560';

    try {
      final result = await Process.run(
        _ffmpegPath,
        [
          '-i', audioPath,
          '-filter_complex',
          'showwavespic=s=${width}x$height:colors=$waveColor:split_channels=1',
          '-frames:v', '1',
          '-y',
          outputPath,
        ],
      );

      if (result.exitCode == 0 && await File(outputPath).exists()) {
        return outputPath;
      }
    } catch (e) {
      // Generation failed
    }

    return null;
  }

  /// Generate a spectrum image for an audio file
  Future<String?> generateSpectrum(
    String audioPath, {
    int width = 800,
    int height = 200,
  }) async {
    if (_cacheDir == null) {
      await initialize();
    }

    if (_cacheDir == null) return null;

    final hash = audioPath.hashCode.toRadixString(16);
    final outputPath = p.join(_cacheDir!.path, 'spectrum_$hash.png');

    // Check cache
    if (await File(outputPath).exists()) {
      return outputPath;
    }

    try {
      final result = await Process.run(
        _ffmpegPath,
        [
          '-i', audioPath,
          '-lavfi',
          'showspectrumpic=s=${width}x$height:mode=separate:color=intensity',
          '-frames:v', '1',
          '-y',
          outputPath,
        ],
      );

      if (result.exitCode == 0 && await File(outputPath).exists()) {
        return outputPath;
      }
    } catch (e) {
      // Generation failed
    }

    return null;
  }

  /// Clear the waveform cache
  Future<void> clearCache() async {
    if (_cacheDir == null) return;

    try {
      if (await _cacheDir!.exists()) {
        await _cacheDir!.delete(recursive: true);
        await _cacheDir!.create(recursive: true);
      }
    } catch (e) {
      // Failed to clear cache
    }
  }

  /// Get cache size in bytes
  Future<int> getCacheSize() async {
    if (_cacheDir == null) return 0;

    try {
      if (!await _cacheDir!.exists()) return 0;

      int totalSize = 0;
      await for (final entity in _cacheDir!.list(recursive: true)) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }
      return totalSize;
    } catch (e) {
      return 0;
    }
  }

  /// Format bytes to human readable string
  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
