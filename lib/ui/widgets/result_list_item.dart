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
            ],
          ),
        ),
      ),
    );
  }

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
