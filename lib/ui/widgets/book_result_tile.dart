import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/book_scan_result.dart';
import '../../models/scan_result.dart';
import '../../utils/time_formatter.dart';

/// A tile widget that displays a grouped audiobook result with expandable file list
class BookResultTile extends StatefulWidget {
  final BookScanResult book;
  final ScanResult? selectedResult;
  final Function(ScanResult) onFileSelected;
  final bool initiallyExpanded;

  const BookResultTile({
    super.key,
    required this.book,
    required this.selectedResult,
    required this.onFileSelected,
    this.initiallyExpanded = false,
  });

  @override
  State<BookResultTile> createState() => _BookResultTileState();
}

class _BookResultTileState extends State<BookResultTile> {
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    // Auto-expand if there are failed files, otherwise use initial value
    _isExpanded = widget.book.failedCount > 0 || widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final book = widget.book;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Book header row (clickable to expand/collapse)
        Material(
          color: _isExpanded
              ? colorScheme.surfaceContainerHighest.withAlpha(80)
              : Colors.transparent,
          child: InkWell(
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: colorScheme.outline.withAlpha(30),
                  ),
                ),
              ),
              child: Row(
                children: [
                  // Expand/collapse icon
                  Icon(
                    _isExpanded ? Icons.expand_more : Icons.chevron_right,
                    size: 20,
                    color: colorScheme.outline,
                  ),
                  const SizedBox(width: 8),
                  // Status icon
                  _buildStatusIcon(colorScheme),
                  const SizedBox(width: 12),
                  // Cover art (small)
                  if (book.coverArtPath != null && File(book.coverArtPath!).existsSync()) ...[
                    Container(
                      height: 40,
                      constraints: const BoxConstraints(maxWidth: 56),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(30),
                            blurRadius: 2,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.file(
                          File(book.coverArtPath!),
                          height: 40,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) =>
                              const SizedBox(width: 40, height: 40),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  // Book name and file count
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          book.bookName,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _buildStatusText(),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: book.isAllPassed ? Colors.green : Colors.orange,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Audio duration
                  if (book.totalAudioDuration.inSeconds > 0) ...[
                    const SizedBox(width: 8),
                    Text(
                      TimeFormatter.formatBookLength(book.totalAudioDuration),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.outline,
                      ),
                    ),
                  ],
                  // Scan time
                  if (book.totalScanDuration.inMilliseconds > 0) ...[
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        TimeFormatter.formatScanTime(book.totalScanDuration),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.outline,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        // Expanded file list
        if (_isExpanded) ...[
          // Show failed files first, then passed files
          ...book.failedFiles.map((file) => _buildFileRow(file, colorScheme, theme)),
          ...book.passedFiles.map((file) => _buildFileRow(file, colorScheme, theme)),
        ],
      ],
    );
  }

  Widget _buildFileRow(ScanResult file, ColorScheme colorScheme, ThemeData theme) {
    final isSelected = widget.selectedResult == file;

    return Material(
      color: isSelected
          ? colorScheme.primaryContainer.withAlpha(100)
          : Colors.transparent,
      child: InkWell(
        onTap: () => widget.onFileSelected(file),
        child: Container(
          padding: const EdgeInsets.only(left: 56, right: 16, top: 8, bottom: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: colorScheme.outline.withAlpha(20),
              ),
            ),
          ),
          child: Row(
            children: [
              // File status icon
              _buildFileStatusIcon(file, colorScheme),
              const SizedBox(width: 12),
              // File name and status
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.fileName,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (!file.isOk) ...[
                      const SizedBox(height: 1),
                      Text(
                        file.statusDescription,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: _getFileStatusColor(file, colorScheme),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              // File duration
              if (file.duration != null) ...[
                const SizedBox(width: 8),
                Text(
                  TimeFormatter.formatBookLength(file.duration!),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.outline,
                  ),
                ),
              ],
              // File scan time
              if (file.scanDuration != null) ...[
                const SizedBox(width: 8),
                Text(
                  TimeFormatter.formatScanTime(file.scanDuration!),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.outline.withAlpha(180),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusIcon(ColorScheme colorScheme) {
    if (widget.book.isAllPassed) {
      return const Icon(Icons.check_circle, color: Colors.green, size: 24);
    } else {
      return const Icon(Icons.warning, color: Colors.orange, size: 24);
    }
  }

  Widget _buildFileStatusIcon(ScanResult result, ColorScheme colorScheme) {
    IconData icon;
    Color color;

    switch (result.status) {
      case ScanResultStatus.ok:
        icon = Icons.check_circle_outline;
        color = Colors.green;
      case ScanResultStatus.missingAudio:
        icon = Icons.warning;
        color = Colors.orange;
      case ScanResultStatus.corrupt:
        icon = Icons.error;
        color = Colors.red;
      case ScanResultStatus.truncated:
        icon = Icons.content_cut;
        color = Colors.deepOrange;
      case ScanResultStatus.silence:
        icon = Icons.volume_off;
        color = Colors.amber;
      case ScanResultStatus.chapterSilence:
        icon = Icons.bookmark_border;
        color = Colors.purple;
      case ScanResultStatus.error:
        icon = Icons.error_outline;
        color = colorScheme.error;
    }

    return Icon(icon, color: color, size: 18);
  }

  Color _getFileStatusColor(ScanResult result, ColorScheme colorScheme) {
    switch (result.status) {
      case ScanResultStatus.ok:
        return Colors.green;
      case ScanResultStatus.missingAudio:
        return Colors.orange;
      case ScanResultStatus.corrupt:
        return Colors.red;
      case ScanResultStatus.truncated:
        return Colors.deepOrange;
      case ScanResultStatus.silence:
        return Colors.amber.shade700;
      case ScanResultStatus.chapterSilence:
        return Colors.purple;
      case ScanResultStatus.error:
        return colorScheme.error;
    }
  }

  String _buildStatusText() {
    final book = widget.book;
    if (book.isAllPassed) {
      return '${book.passedCount} of ${book.totalCount} passed';
    } else {
      return '${book.failedCount} of ${book.totalCount} flagged';
    }
  }
}
