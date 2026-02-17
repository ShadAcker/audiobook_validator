/// Utility class for formatting durations in a human-readable way
class TimeFormatter {
  /// Format a duration in a smart adaptive format
  /// - Less than 60s: "45s"
  /// - Less than 60m: "1m 23s"
  /// - 60m or more: "2h 15m"
  static String formatScanTime(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (totalSeconds < 60) {
      return '${seconds}s';
    } else if (hours == 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${hours}h ${minutes}m';
    }
  }

  /// Format a duration for book/audio length display
  /// - Less than 60m: "45m 30s"
  /// - 60m or more: "2h 15m"
  static String formatBookLength(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m ${seconds}s';
  }

  /// Format milliseconds as a duration string
  static String formatMilliseconds(int milliseconds) {
    return formatScanTime(Duration(milliseconds: milliseconds));
  }
}
