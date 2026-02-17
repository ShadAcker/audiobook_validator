import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/scan_result.dart';

/// Callback for file scan progress updates
typedef FileScanProgressCallback = void Function(FileScanProgress progress);

/// Represents progress while scanning a single file
class FileScanProgress {
  final String fileName;
  final ScanPhase phase;
  final double phaseProgress; // 0.0 to 1.0
  final int? segmentsCurrent;
  final int? segmentsTotal;
  final Duration? fileDuration;
  final String? details;

  FileScanProgress({
    required this.fileName,
    required this.phase,
    this.phaseProgress = 0.0,
    this.segmentsCurrent,
    this.segmentsTotal,
    this.fileDuration,
    this.details,
  });

  String get phaseDescription {
    switch (phase) {
      case ScanPhase.probing:
        return 'Analyzing file info...';
      case ScanPhase.checkingCorruption:
        if (segmentsTotal != null && segmentsTotal! > 1) {
          return 'Checking corruption (${segmentsCurrent ?? 0}/$segmentsTotal)';
        }
        return 'Checking for corruption...';
      case ScanPhase.checkingTruncation:
        return 'Checking for truncated data...';
      case ScanPhase.detectingSilence:
        if (segmentsTotal != null && segmentsTotal! > 1) {
          return 'Scanning for silence (${segmentsCurrent ?? 0}/$segmentsTotal segments)';
        }
        return 'Detecting silence...';
      case ScanPhase.analyzingChapters:
        return 'Analyzing chapters...';
      case ScanPhase.complete:
        return 'Complete';
    }
  }
}

/// Phases of scanning a single file
enum ScanPhase {
  probing,
  checkingCorruption,
  checkingTruncation,
  detectingSilence,
  analyzingChapters,
  complete,
}

/// Service for scanning audio files using FFmpeg and FFprobe
class AudioScannerService {
  // Default FFmpeg paths - can be overridden
  String _ffmpegPath = 'ffmpeg';
  String _ffprobePath = 'ffprobe';

  // Scanning settings
  double silenceThresholdDb = -50.0;
  double silenceDurationSec = 10.0;
  bool detectChapterSilence = true;
  
  /// Scan mode: 'full' scans entire file, 'sample' only checks segments
  String scanMode = 'sample';
  
  /// For sample mode: number of segments to check
  int sampleSegments = 10;

  // Supported audio extensions
  static const supportedExtensions = ['.mp3', '.m4b', '.m4a', '.aac', '.wav', '.flac', '.ogg'];

  AudioScannerService();

  /// Set custom FFmpeg/FFprobe paths
  void setFfmpegPaths({String? ffmpegPath, String? ffprobePath}) {
    if (ffmpegPath != null) _ffmpegPath = ffmpegPath;
    if (ffprobePath != null) _ffprobePath = ffprobePath;
  }

  /// Check if FFmpeg and FFprobe are available
  Future<bool> checkFfmpegAvailable() async {
    try {
      final ffmpegResult = await Process.run(_ffmpegPath, ['-version']);
      final ffprobeResult = await Process.run(_ffprobePath, ['-version']);
      return ffmpegResult.exitCode == 0 && ffprobeResult.exitCode == 0;
    } catch (e) {
      return false;
    }
  }

  /// Get FFmpeg version info
  Future<String?> getFfmpegVersion() async {
    try {
      final result = await Process.run(_ffmpegPath, ['-version']);
      if (result.exitCode == 0) {
        final lines = (result.stdout as String).split('\n');
        return lines.isNotEmpty ? lines.first : null;
      }
    } catch (e) {
      return null;
    }
    return null;
  }

  /// Recursively find all audio files in a directory
  Future<List<String>> findAudioFiles(String directoryPath) async {
    final dir = Directory(directoryPath);
    if (!await dir.exists()) return [];

    final List<String> audioFiles = [];
    
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        final ext = p.extension(entity.path).toLowerCase();
        if (supportedExtensions.contains(ext)) {
          audioFiles.add(entity.path);
        }
      }
    }

    audioFiles.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return audioFiles;
  }

  /// Scan a single audio file
  Future<ScanResult> scanFile(
    String filePath, {
    String scanMode = 'sample',
    FileScanProgressCallback? onProgress,
  }) async {
    final fileName = p.basename(filePath);

    void reportProgress(ScanPhase phase, {double progress = 0.0, int? segmentsCurrent, int? segmentsTotal, Duration? fileDuration, String? details}) {
      onProgress?.call(FileScanProgress(
        fileName: fileName,
        phase: phase,
        phaseProgress: progress,
        segmentsCurrent: segmentsCurrent,
        segmentsTotal: segmentsTotal,
        fileDuration: fileDuration,
        details: details,
      ));
    }

    try {
      // Step 1: Check if file exists
      if (!await File(filePath).exists()) {
        return ScanResult(
          path: filePath,
          fileName: fileName,
          hasAudioStream: false,
          error: 'File not found',
        );
      }

      // Step 2: Get file info using ffprobe
      reportProgress(ScanPhase.probing);
      final probeResult = await _probeFile(filePath);
      if (probeResult['error'] != null) {
        return ScanResult(
          path: filePath,
          fileName: fileName,
          hasAudioStream: false,
          error: probeResult['error'],
        );
      }

      final hasAudioStream = probeResult['hasAudio'] == true;
      if (!hasAudioStream) {
        return ScanResult(
          path: filePath,
          fileName: fileName,
          hasAudioStream: false,
          duration: probeResult['duration'],
          codec: probeResult['codec'],
          bitrate: probeResult['bitrate'],
          sampleRate: probeResult['sampleRate'],
          chapters: probeResult['chapters'] ?? [],
        );
      }

      final duration = probeResult['duration'] as Duration?;
      final chapters = probeResult['chapters'] as List<ChapterInfo>? ?? [];

      // Step 3: Check for corruption (samples start/middle/end for long files)
      reportProgress(ScanPhase.checkingCorruption, fileDuration: duration);
      final isCorrupt = await _checkCorruption(
        filePath,
        fileDuration: duration,
        scanMode: scanMode,
        onProgress: (current, total) {
          reportProgress(
            ScanPhase.checkingCorruption,
            progress: total > 0 ? current / total : 0,
            segmentsCurrent: current,
            segmentsTotal: total,
            fileDuration: duration,
          );
        },
      );

      // Step 4: Check for truncation (metadata claims longer duration than actual data)
      reportProgress(ScanPhase.checkingTruncation, fileDuration: duration);
      final truncationResult = await _checkTruncation(filePath, duration);
      final isTruncated = truncationResult['isTruncated'] as bool;
      final actualDuration = truncationResult['actualDuration'] as Duration?;

      // Step 5: Detect silence
      reportProgress(ScanPhase.detectingSilence, fileDuration: duration);
      final silenceIntervals = await _detectSilence(
        filePath,
        fileDuration: duration,
        chapters: chapters,
        scanMode: scanMode,
        onProgress: (current, total) {
          reportProgress(
            ScanPhase.detectingSilence,
            progress: total > 0 ? current / total : 0,
            segmentsCurrent: current,
            segmentsTotal: total,
            fileDuration: duration,
          );
        },
      );
      final hasLongSilence = silenceIntervals.isNotEmpty;

      // Step 6: Check for chapter-level silence
      reportProgress(ScanPhase.analyzingChapters, fileDuration: duration);
      List<ChapterSilenceInfo> chapterSilenceDetails = [];
      bool hasChapterSilence = false;

      if (detectChapterSilence && chapters.isNotEmpty) {
        chapterSilenceDetails = _detectChapterSilence(chapters, silenceIntervals);
        hasChapterSilence = chapterSilenceDetails.isNotEmpty;
      }

      reportProgress(ScanPhase.complete, progress: 1.0, fileDuration: duration);

      return ScanResult(
        path: filePath,
        fileName: fileName,
        hasAudioStream: hasAudioStream,
        isCorrupt: isCorrupt,
        isTruncated: isTruncated,
        hasLongSilence: hasLongSilence,
        hasChapterSilence: hasChapterSilence,
        silenceIntervals: silenceIntervals,
        chapters: chapters,
        chapterSilenceDetails: chapterSilenceDetails,
        duration: duration,
        actualDuration: actualDuration,
        codec: probeResult['codec'],
        bitrate: probeResult['bitrate'],
        sampleRate: probeResult['sampleRate'],
      );
    } catch (e) {
      return ScanResult(
        path: filePath,
        fileName: fileName,
        hasAudioStream: false,
        error: 'Scan error: $e',
      );
    }
  }

  /// Scan multiple files with progress callback
  /// Yields both file scan progress updates and file completion updates
  Stream<ScanProgress> scanFiles(List<String> filePaths, {String scanMode = 'sample'}) async* {
    final total = filePaths.length;
    
    for (var i = 0; i < total; i++) {
      final filePath = filePaths[i];
      FileScanProgress? lastProgress;
      
      final result = await scanFile(
        filePath,
        scanMode: scanMode,
        onProgress: (progress) {
          lastProgress = progress;
        },
      );
      
      // Yield file completion
      yield ScanProgress(
        current: i + 1,
        total: total,
        result: result,
        isComplete: i + 1 == total,
        fileProgress: lastProgress,
      );
    }
  }
  
  /// Scan multiple files with real-time progress updates
  /// This version yields progress updates during each file scan
  Stream<ScanProgress> scanFilesWithProgress(List<String> filePaths, {String scanMode = 'sample'}) {
    final controller = StreamController<ScanProgress>();
    final total = filePaths.length;
    
    () async {
      for (var i = 0; i < total; i++) {
        final filePath = filePaths[i];
        
        final result = await scanFile(
          filePath,
          scanMode: scanMode,
          onProgress: (progress) {
            // Emit progress update during file scan
            controller.add(ScanProgress(
              current: i,
              total: total,
              isComplete: false,
              fileProgress: progress,
            ));
          },
        );
        
        // Emit file completion
        controller.add(ScanProgress(
          current: i + 1,
          total: total,
          result: result,
          isComplete: i + 1 == total,
        ));
      }
      await controller.close();
    }();
    
    return controller.stream;
  }

  /// Probe file using ffprobe to get metadata
  Future<Map<String, dynamic>> _probeFile(String filePath) async {
    try {
      final result = await Process.run(
        _ffprobePath,
        [
          '-v', 'quiet',
          '-print_format', 'json',
          '-show_format',
          '-show_streams',
          '-show_chapters',
          filePath,
        ],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );

      if (result.exitCode != 0) {
        return {'error': 'FFprobe failed: ${result.stderr}'};
      }

      final json = jsonDecode(result.stdout as String);
      
      // Check for audio stream
      final streams = json['streams'] as List?;
      bool hasAudio = false;
      String? codec;
      int? bitrate;
      int? sampleRate;

      if (streams != null) {
        for (final stream in streams) {
          if (stream['codec_type'] == 'audio') {
            hasAudio = true;
            codec = stream['codec_name'];
            sampleRate = int.tryParse(stream['sample_rate']?.toString() ?? '');
            bitrate = int.tryParse(stream['bit_rate']?.toString() ?? '');
            break;
          }
        }
      }

      // Get duration
      Duration? duration;
      final format = json['format'];
      if (format != null) {
        final durationStr = format['duration']?.toString();
        if (durationStr != null) {
          final durationSec = double.tryParse(durationStr);
          if (durationSec != null) {
            duration = Duration(milliseconds: (durationSec * 1000).round());
          }
        }
        bitrate ??= int.tryParse(format['bit_rate']?.toString() ?? '');
      }

      // Parse chapters
      List<ChapterInfo> chapters = [];
      final chaptersJson = json['chapters'] as List?;
      if (chaptersJson != null) {
        for (var i = 0; i < chaptersJson.length; i++) {
          final ch = chaptersJson[i];
          final tags = ch['tags'] as Map<String, dynamic>?;
          chapters.add(ChapterInfo(
            index: i,
            title: tags?['title'] ?? 'Chapter ${i + 1}',
            startSeconds: (ch['start_time'] is String)
                ? double.tryParse(ch['start_time']) ?? 0
                : (ch['start_time'] ?? 0).toDouble(),
            endSeconds: (ch['end_time'] is String)
                ? double.tryParse(ch['end_time']) ?? 0
                : (ch['end_time'] ?? 0).toDouble(),
          ));
        }
      }

      return {
        'hasAudio': hasAudio,
        'codec': codec,
        'bitrate': bitrate,
        'sampleRate': sampleRate,
        'duration': duration,
        'chapters': chapters,
      };
    } catch (e) {
      return {'error': 'Probe error: $e'};
    }
  }

  /// Check for file corruption using ffmpeg
  /// For long files, checks start, middle, and end sections
  Future<bool> _checkCorruption(
    String filePath, {
    Duration? fileDuration,
    String scanMode = 'sample',
    void Function(int current, int total)? onProgress,
  }) async {
    try {
      // Determine how much to check based on file length
      final durationSec = fileDuration?.inSeconds ?? 600;
      
      // For short files or full mode, check everything
      if (scanMode == 'full' || durationSec <= 600) {
        // For files <= 10 minutes or full mode, check the whole thing
        onProgress?.call(1, 1);
        return await _checkCorruptionSegment(filePath);
      } else {
        // For longer files in sample mode, check start (2min), middle (2min), end (2min)
        final middleStart = (durationSec / 2 - 60).round();
        final endStart = (durationSec - 120).round();
        
        // Check start
        onProgress?.call(1, 3);
        if (await _checkCorruptionSegment(filePath, startSec: 0, durationSec: 120)) {
          return true;
        }
        // Check middle
        onProgress?.call(2, 3);
        if (await _checkCorruptionSegment(filePath, startSec: middleStart, durationSec: 120)) {
          return true;
        }
        // Check end
        onProgress?.call(3, 3);
        if (await _checkCorruptionSegment(filePath, startSec: endStart, durationSec: 120)) {
          return true;
        }
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  /// Check a specific segment of a file for corruption
  Future<bool> _checkCorruptionSegment(String filePath, {int? startSec, int? durationSec}) async {
    try {
      final args = <String>[
        '-v', 'error',
        '-i', filePath,
      ];
      
      if (startSec != null) {
        args.addAll(['-ss', startSec.toString()]);
      }
      if (durationSec != null) {
        args.addAll(['-t', durationSec.toString()]);
      }
      args.addAll(['-f', 'null', '-']);

      final result = await Process.run(
        _ffmpegPath,
        args,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );

      final stderr = result.stderr as String;
      return stderr.contains('Invalid data') ||
          stderr.contains('Error while decoding') ||
          stderr.contains('corrupt') ||
          stderr.contains('Discarding') ||
          (stderr.isNotEmpty && result.exitCode != 0);
    } catch (e) {
      return false;
    }
  }

  /// Check if file is truncated (metadata claims longer duration than actual data)
  /// Returns a map with 'isTruncated' and 'actualDuration'
  Future<Map<String, dynamic>> _checkTruncation(String filePath, Duration? claimedDuration) async {
    if (claimedDuration == null || claimedDuration.inSeconds < 60) {
      return {'isTruncated': false, 'actualDuration': claimedDuration};
    }

    try {
      final claimedSec = claimedDuration.inSeconds;
      
      // First, try to read at 90% of claimed duration
      // If that works, the file is probably not truncated
      final testPoint = (claimedSec * 0.9).round();
      if (await _hasAudioAt(filePath, testPoint)) {
        return {'isTruncated': false, 'actualDuration': claimedDuration};
      }

      // File appears truncated - binary search to find where audio actually ends
      var low = 0;
      var high = claimedSec;
      
      // First find a point where we know audio exists
      for (final checkpoint in [60, 300, 600, 1200]) {
        if (checkpoint < claimedSec) {
          if (await _hasAudioAt(filePath, checkpoint)) {
            low = checkpoint;
          } else {
            high = checkpoint;
            break;
          }
        }
      }

      // Binary search between low and high
      while ((high - low) > 30) {
        final mid = (low + high) ~/ 2;
        if (await _hasAudioAt(filePath, mid)) {
          low = mid;
        } else {
          high = mid;
        }
      }

      final actualDuration = Duration(seconds: low);
      
      // Only report as truncated if we're missing more than 5% of the file
      final missingPercent = (claimedSec - low) / claimedSec;
      final isTruncated = missingPercent > 0.05;

      return {
        'isTruncated': isTruncated,
        'actualDuration': actualDuration,
      };
    } catch (e) {
      return {'isTruncated': false, 'actualDuration': claimedDuration};
    }
  }

  /// Check if audio data exists at a specific time point
  Future<bool> _hasAudioAt(String filePath, int seekSeconds) async {
    try {
      final tempFile = p.join(Directory.systemTemp.path, 'av_truncation_check_${DateTime.now().millisecondsSinceEpoch}.m4a');
      
      await Process.run(
        _ffmpegPath,
        [
          '-hide_banner',
          '-y',
          '-ss', seekSeconds.toString(),
          '-i', filePath,
          '-t', '3',
          '-c', 'copy',
          tempFile,
        ],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );

      final file = File(tempFile);
      if (await file.exists()) {
        final size = await file.length();
        await file.delete();
        // If we got more than ~15KB, there's actual audio (not just headers/cover art)
        return size > 15000;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Detect silence in audio file
  /// For long files in 'sample' mode, checks segments at regular intervals
  /// and around chapter boundaries
  Future<List<SilenceInterval>> _detectSilence(
    String filePath, {
    Duration? fileDuration,
    List<ChapterInfo>? chapters,
    String scanMode = 'sample',
    void Function(int current, int total)? onProgress,
  }) async {
    try {
      final durationSec = fileDuration?.inSeconds ?? 0;
      
      // For short files (< 30 min) or full mode, scan entire file
      if (scanMode == 'full' || durationSec < 1800) {
        onProgress?.call(1, 1);
        return await _detectSilenceInSegment(filePath);
      }
      
      // For long files in sample mode:
      // 1. Check start, middle, end
      // 2. Check around each chapter boundary
      final allIntervals = <SilenceInterval>[];
      final segmentDuration = 120; // 2 minutes per segment
      
      // Calculate segments to check
      final segmentsToCheck = <int>{}; // Set of start times
      
      // Always check start
      segmentsToCheck.add(0);
      
      // Check evenly spaced segments
      final spacing = durationSec ~/ sampleSegments;
      for (var i = 1; i < sampleSegments; i++) {
        segmentsToCheck.add(spacing * i);
      }
      
      // Check end (start 2 min before end)
      segmentsToCheck.add((durationSec - segmentDuration).clamp(0, durationSec));
      
      // Check around chapter boundaries (±30 seconds from each chapter start)
      if (chapters != null && detectChapterSilence) {
        for (final chapter in chapters) {
          final chapterStart = chapter.startSeconds.round();
          // Check 1 minute before and after chapter boundary
          segmentsToCheck.add((chapterStart - 60).clamp(0, durationSec - segmentDuration));
        }
      }
      
      // Sort and check each segment
      final sortedSegments = segmentsToCheck.toList()..sort();
      final totalSegments = sortedSegments.length;
      var currentSegment = 0;
      
      for (final startSec in sortedSegments) {
        currentSegment++;
        onProgress?.call(currentSegment, totalSegments);
        
        final intervals = await _detectSilenceInSegment(
          filePath,
          startSec: startSec,
          durationSec: segmentDuration,
        );
        
        // Adjust timestamps to absolute positions
        for (final interval in intervals) {
          allIntervals.add(SilenceInterval(
            startSeconds: interval.startSeconds + startSec,
            endSeconds: interval.endSeconds + startSec,
            durationSeconds: interval.durationSeconds,
          ));
        }
      }
      
      // Remove duplicates (overlapping segments might find same silence)
      return _deduplicateSilenceIntervals(allIntervals);
    } catch (e) {
      return [];
    }
  }

  /// Detect silence in a specific segment of the file
  Future<List<SilenceInterval>> _detectSilenceInSegment(
    String filePath, {
    int? startSec,
    int? durationSec,
  }) async {
    try {
      final args = <String>['-i', filePath];
      
      if (startSec != null) {
        args.insertAll(0, ['-ss', startSec.toString()]);
      }
      if (durationSec != null) {
        args.addAll(['-t', durationSec.toString()]);
      }
      
      args.addAll([
        '-af', 'silencedetect=noise=${silenceThresholdDb}dB:d=$silenceDurationSec',
        '-f', 'null',
        '-',
      ]);

      final result = await Process.run(
        _ffmpegPath,
        args,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );

      final stderr = result.stderr as String;
      return _parseSilenceOutput(stderr);
    } catch (e) {
      return [];
    }
  }

  /// Remove duplicate/overlapping silence intervals
  List<SilenceInterval> _deduplicateSilenceIntervals(List<SilenceInterval> intervals) {
    if (intervals.isEmpty) return [];
    
    intervals.sort((a, b) => a.startSeconds.compareTo(b.startSeconds));
    final result = <SilenceInterval>[intervals.first];
    
    for (var i = 1; i < intervals.length; i++) {
      final current = intervals[i];
      final last = result.last;
      
      // If this interval overlaps or is very close to the previous one, skip it
      if (current.startSeconds <= last.endSeconds + 1) {
        continue;
      }
      result.add(current);
    }
    
    return result;
  }

  /// Parse silence detection output from ffmpeg
  List<SilenceInterval> _parseSilenceOutput(String output) {
    final intervals = <SilenceInterval>[];
    final lines = output.split('\n');

    double? currentStart;
    
    for (final line in lines) {
      // Look for silence_start
      final startMatch = RegExp(r'silence_start:\s*([\d.]+)').firstMatch(line);
      if (startMatch != null) {
        currentStart = double.tryParse(startMatch.group(1) ?? '');
      }

      // Look for silence_end and silence_duration
      final endMatch = RegExp(r'silence_end:\s*([\d.]+)\s*\|\s*silence_duration:\s*([\d.]+)').firstMatch(line);
      if (endMatch != null && currentStart != null) {
        final end = double.tryParse(endMatch.group(1) ?? '') ?? 0;
        final duration = double.tryParse(endMatch.group(2) ?? '') ?? 0;
        
        intervals.add(SilenceInterval(
          startSeconds: currentStart,
          endSeconds: end,
          durationSeconds: duration,
        ));
        currentStart = null;
      }
    }

    return intervals;
  }

  /// Detect silence that occurs after chapter boundaries
  List<ChapterSilenceInfo> _detectChapterSilence(
    List<ChapterInfo> chapters,
    List<SilenceInterval> silenceIntervals,
  ) {
    final results = <ChapterSilenceInfo>[];
    const tolerance = 5.0; // seconds tolerance for matching

    for (final chapter in chapters) {
      for (final silence in silenceIntervals) {
        // Check if silence starts within tolerance of chapter end
        if ((silence.startSeconds - chapter.endSeconds).abs() < tolerance ||
            (silence.startSeconds >= chapter.endSeconds - tolerance &&
             silence.startSeconds <= chapter.endSeconds + tolerance)) {
          results.add(ChapterSilenceInfo(
            chapter: chapter,
            silence: silence,
          ));
          break; // Only report first silence per chapter
        }
      }
    }

    return results;
  }

  /// Re-encode a file to AAC format
  Future<String?> reencodeFile(
    String inputPath, {
    String? outputDir,
    String codec = 'aac',
    int bitrate = 128,
  }) async {
    try {
      outputDir ??= p.join(p.dirname(inputPath), '_fixed_output');
      
      // Create output directory
      await Directory(outputDir).create(recursive: true);

      final fileName = p.basenameWithoutExtension(inputPath);
      final outputPath = p.join(outputDir, '$fileName.m4a');

      final result = await Process.run(
        _ffmpegPath,
        [
          '-i', inputPath,
          '-c:a', codec,
          '-b:a', '${bitrate}k',
          '-y', // Overwrite
          outputPath,
        ],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );

      if (result.exitCode == 0) {
        return outputPath;
      } else {
        return null;
      }
    } catch (e) {
      return null;
    }
  }

  /// Delete a file (requires explicit confirmation from caller)
  Future<bool> deleteFile(String filePath, {required bool confirmed}) async {
    if (!confirmed) return false;
    try {
      await File(filePath).delete();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Move a file to a new location (requires explicit confirmation from caller)
  Future<String?> moveFile(String filePath, String destDir, {required bool confirmed}) async {
    if (!confirmed) return null;
    try {
      await Directory(destDir).create(recursive: true);
      final fileName = p.basename(filePath);
      final destPath = p.join(destDir, fileName);
      await File(filePath).rename(destPath);
      return destPath;
    } catch (e) {
      // If rename fails (cross-device), try copy+delete
      try {
        final fileName = p.basename(filePath);
        final destPath = p.join(destDir, fileName);
        await File(filePath).copy(destPath);
        await File(filePath).delete();
        return destPath;
      } catch (_) {
        return null;
      }
    }
  }
}

/// Progress update during scanning
class ScanProgress {
  final int current;
  final int total;
  final ScanResult? result; // null when this is a file progress update
  final bool isComplete;
  final FileScanProgress? fileProgress; // Progress within current file

  ScanProgress({
    required this.current,
    required this.total,
    this.result,
    required this.isComplete,
    this.fileProgress,
  });

  double get percentage => total > 0 ? current / total : 0;
  
  /// True if this is a progress update within a file (not a file completion)
  bool get isFileProgressUpdate => result == null && fileProgress != null;
}

/// Isolate-based scanner for parallel processing
class IsolateScannerService {
  final AudioScannerService _scanner;

  IsolateScannerService(this._scanner);

  /// Scan files using multiple isolates for parallel processing
  Stream<ScanProgress> scanFilesParallel(
    List<String> filePaths, {
    int maxConcurrent = 4,
  }) async* {
    final total = filePaths.length;
    var completed = 0;
    
    // Process in batches
    for (var i = 0; i < filePaths.length; i += maxConcurrent) {
      final batch = filePaths.skip(i).take(maxConcurrent).toList();
      final futures = batch.map((path) => _scanner.scanFile(path));
      final results = await Future.wait(futures);
      
      for (final result in results) {
        completed++;
        yield ScanProgress(
          current: completed,
          total: total,
          result: result,
          isComplete: completed == total,
        );
      }
    }
  }
}
