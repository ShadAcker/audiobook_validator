import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/scan_result.dart';

/// A list item widget showing scan result summary
class ResultListItem extends StatelessWidget {
  final ScanResult result;
  final bool isSelected;
  final VoidCallback? onTap;

  const ResultListItem({
    super.key,
    required this.result,
    this.isSelected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: isSelected
          ? colorScheme.primaryContainer.withAlpha(100)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
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
              // Status icon on the left
              _buildStatusIcon(colorScheme),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.fileName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      result.statusDescription,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _getStatusColor(colorScheme),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (result.duration != null) ...[
                const SizedBox(width: 8),
                Text(
                  _formatDuration(result.duration!),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.outline,
                  ),
                ),
              ],
              // Cover art on the right
              if (result.coverArtPath != null && File(result.coverArtPath!).existsSync()) ...[
                const SizedBox(width: 16),
                Container(
                  height: 56,
                  constraints: const BoxConstraints(maxWidth: 80),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(40),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.file(
                      File(result.coverArtPath!),
                      height: 56,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => const SizedBox(width: 56, height: 56),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Standard status icon
  Widget _buildStatusIcon(ColorScheme colorScheme) {
    IconData icon;
    Color color;

    switch (result.status) {
      case ScanResultStatus.ok:
        icon = Icons.check_circle;
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

    return Icon(icon, color: color, size: 24);
  }

  Color _getStatusColor(ColorScheme colorScheme) {
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

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final mins = duration.inMinutes.remainder(60);
    final secs = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours}h ${mins}m';
    }
    return '${mins}m ${secs}s';
  }
}
