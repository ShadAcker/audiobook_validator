import 'package:path/path.dart' as p;
import 'scan_result.dart';

/// Represents a group of scan results for a single audiobook (folder)
class BookScanResult {
  final String folderPath;
  final String bookName;
  final List<ScanResult> files;

  BookScanResult({
    required this.folderPath,
    required this.bookName,
    required this.files,
  });

  /// Number of files that passed all checks
  int get passedCount => files.where((f) => f.isOk).length;

  /// Number of files that have issues
  int get failedCount => files.where((f) => !f.isOk).length;

  /// Total number of files in this book
  int get totalCount => files.length;

  /// Whether all files passed
  bool get isAllPassed => failedCount == 0;

  /// Get only the files that have issues
  List<ScanResult> get failedFiles => files.where((f) => !f.isOk).toList();

  /// Get only the files that passed
  List<ScanResult> get passedFiles => files.where((f) => f.isOk).toList();

  /// Total scan duration for all files in this book
  Duration get totalScanDuration {
    int totalMs = 0;
    for (final file in files) {
      if (file.scanDuration != null) {
        totalMs += file.scanDuration!.inMilliseconds;
      }
    }
    return Duration(milliseconds: totalMs);
  }

  /// Total audio duration for all files in this book
  Duration get totalAudioDuration {
    int totalSeconds = 0;
    for (final file in files) {
      if (file.duration != null) {
        totalSeconds += file.duration!.inSeconds;
      }
    }
    return Duration(seconds: totalSeconds);
  }

  /// Get cover art path from first file that has one
  String? get coverArtPath {
    for (final file in files) {
      if (file.coverArtPath != null) {
        return file.coverArtPath;
      }
    }
    return null;
  }

  /// Group a list of scan results by their parent folder
  static List<BookScanResult> groupByBook(List<ScanResult> results) {
    final Map<String, List<ScanResult>> grouped = {};

    for (final result in results) {
      final folderPath = p.dirname(result.path);
      grouped.putIfAbsent(folderPath, () => []);
      grouped[folderPath]!.add(result);
    }

    final books = grouped.entries.map((entry) {
      return BookScanResult(
        folderPath: entry.key,
        bookName: p.basename(entry.key),
        files: entry.value,
      );
    }).toList();

    // Sort books by name
    books.sort((a, b) => a.bookName.toLowerCase().compareTo(b.bookName.toLowerCase()));

    return books;
  }
}
