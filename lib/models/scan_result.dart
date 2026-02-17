/// Represents the result of scanning a single audio file
class ScanResult {
  final String path;
  final String fileName;
  final bool hasAudioStream;
  final bool isCorrupt;
  final bool isTruncated;
  final bool hasLongSilence;
  final bool hasChapterSilence;
  final List<SilenceInterval> silenceIntervals;
  final List<ChapterInfo> chapters;
  final List<ChapterSilenceInfo> chapterSilenceDetails;
  final String? error;
  final Duration? duration;
  final Duration? actualDuration; // Actual playable duration (may differ from metadata)
  final String? codec;
  final int? bitrate;
  final int? sampleRate;

  ScanResult({
    required this.path,
    required this.fileName,
    this.hasAudioStream = true,
    this.isCorrupt = false,
    this.isTruncated = false,
    this.hasLongSilence = false,
    this.hasChapterSilence = false,
    this.silenceIntervals = const [],
    this.chapters = const [],
    this.chapterSilenceDetails = const [],
    this.error,
    this.duration,
    this.actualDuration,
    this.codec,
    this.bitrate,
    this.sampleRate,
  });

  bool get isOk =>
      hasAudioStream && !isCorrupt && !isTruncated && !hasLongSilence && !hasChapterSilence && error == null;

  ScanResultStatus get status {
    if (error != null) return ScanResultStatus.error;
    if (!hasAudioStream) return ScanResultStatus.missingAudio;
    if (isCorrupt) return ScanResultStatus.corrupt;
    if (isTruncated) return ScanResultStatus.truncated;
    if (hasChapterSilence) return ScanResultStatus.chapterSilence;
    if (hasLongSilence) return ScanResultStatus.silence;
    return ScanResultStatus.ok;
  }

  String get statusDescription {
    switch (status) {
      case ScanResultStatus.ok:
        return 'OK';
      case ScanResultStatus.missingAudio:
        return 'Missing audio stream';
      case ScanResultStatus.corrupt:
        return 'File is corrupt';
      case ScanResultStatus.truncated:
        return 'File is truncated (${_formatDuration(actualDuration)} of ${_formatDuration(duration)} playable)';
      case ScanResultStatus.silence:
        return 'Long silence detected (${silenceIntervals.length} interval${silenceIntervals.length == 1 ? '' : 's'})';
      case ScanResultStatus.chapterSilence:
        return 'Silence after chapter (${chapterSilenceDetails.length} chapter${chapterSilenceDetails.length == 1 ? '' : 's'})';
      case ScanResultStatus.error:
        return error ?? 'Unknown error';
    }
  }

  String _formatDuration(Duration? d) {
    if (d == null) return 'unknown';
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${d.inMinutes}m';
  }

  Map<String, dynamic> toJson() => {
        'path': path,
        'fileName': fileName,
        'hasAudioStream': hasAudioStream,
        'isCorrupt': isCorrupt,
        'isTruncated': isTruncated,
        'hasLongSilence': hasLongSilence,
        'hasChapterSilence': hasChapterSilence,
        'silenceIntervals': silenceIntervals.map((s) => s.toJson()).toList(),
        'chapters': chapters.map((c) => c.toJson()).toList(),
        'chapterSilenceDetails': chapterSilenceDetails.map((c) => c.toJson()).toList(),
        'error': error,
        'duration': duration?.inSeconds,
        'actualDuration': actualDuration?.inSeconds,
        'codec': codec,
        'bitrate': bitrate,
        'sampleRate': sampleRate,
        'status': status.name,
        'statusDescription': statusDescription,
      };

  List<String> toCsvRow() => [
        path,
        fileName,
        status.name,
        statusDescription,
        hasAudioStream.toString(),
        isCorrupt.toString(),
        isTruncated.toString(),
        hasLongSilence.toString(),
        hasChapterSilence.toString(),
        silenceIntervals.length.toString(),
        chapters.length.toString(),
        duration?.inSeconds.toString() ?? '',
        actualDuration?.inSeconds.toString() ?? '',
        codec ?? '',
        bitrate?.toString() ?? '',
        error ?? '',
      ];

  static List<String> csvHeaders() => [
        'Path',
        'File Name',
        'Status',
        'Status Description',
        'Has Audio Stream',
        'Is Corrupt',
        'Is Truncated',
        'Has Long Silence',
        'Has Chapter Silence',
        'Silence Intervals',
        'Chapters',
        'Duration (sec)',
        'Actual Duration (sec)',
        'Codec',
        'Bitrate',
        'Error',
      ];
}

enum ScanResultStatus {
  ok,
  missingAudio,
  corrupt,
  truncated,
  silence,
  chapterSilence,
  error,
}

/// Represents a detected silence interval
class SilenceInterval {
  final double startSeconds;
  final double endSeconds;
  final double durationSeconds;

  SilenceInterval({
    required this.startSeconds,
    required this.endSeconds,
    required this.durationSeconds,
  });

  Map<String, dynamic> toJson() => {
        'startSeconds': startSeconds,
        'endSeconds': endSeconds,
        'durationSeconds': durationSeconds,
      };

  @override
  String toString() =>
      '${_formatTime(startSeconds)} - ${_formatTime(endSeconds)} (${durationSeconds.toStringAsFixed(1)}s)';

  String _formatTime(double seconds) {
    final hours = (seconds / 3600).floor();
    final mins = ((seconds % 3600) / 60).floor();
    final secs = (seconds % 60).floor();
    if (hours > 0) {
      return '$hours:${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }
}

/// Represents a chapter in an audiobook
class ChapterInfo {
  final int index;
  final String title;
  final double startSeconds;
  final double endSeconds;

  ChapterInfo({
    required this.index,
    required this.title,
    required this.startSeconds,
    required this.endSeconds,
  });

  Map<String, dynamic> toJson() => {
        'index': index,
        'title': title,
        'startSeconds': startSeconds,
        'endSeconds': endSeconds,
      };
}

/// Represents silence detected after a chapter
class ChapterSilenceInfo {
  final ChapterInfo chapter;
  final SilenceInterval silence;

  ChapterSilenceInfo({
    required this.chapter,
    required this.silence,
  });

  Map<String, dynamic> toJson() => {
        'chapter': chapter.toJson(),
        'silence': silence.toJson(),
      };

  @override
  String toString() =>
      'After "${chapter.title}": ${silence.durationSeconds.toStringAsFixed(1)}s silence';
}
