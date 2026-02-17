import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/scan_result.dart';
import '../../services/waveform_service.dart';

/// Detailed view of a scan result
class ScanResultDetails extends StatefulWidget {
  final ScanResult result;

  const ScanResultDetails({super.key, required this.result});

  @override
  State<ScanResultDetails> createState() => _ScanResultDetailsState();
}

class _ScanResultDetailsState extends State<ScanResultDetails> {
  final WaveformService _waveformService = WaveformService();
  String? _waveformPath;
  bool _isGeneratingWaveform = false;

  @override
  void didUpdateWidget(ScanResultDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.result.path != widget.result.path) {
      _waveformPath = null;
    }
  }

  Future<void> _generateWaveform() async {
    setState(() => _isGeneratingWaveform = true);
    
    final path = await _waveformService.generateWaveform(widget.result.path);
    
    if (mounted) {
      setState(() {
        _waveformPath = path;
        _isGeneratingWaveform = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with optional cover art
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cover art (if available)
              if (widget.result.coverArtPath != null) ...[
                Container(
                  height: 120,
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(widget.result.coverArtPath!),
                      height: 120,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.music_note,
                          size: 48,
                          color: colorScheme.outline,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'File Details',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    // Status card
                    _buildStatusCard(colorScheme),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // File info
          _buildSection(
            title: 'File Information',
            children: [
              _buildInfoRow('Path', widget.result.path),
              if (widget.result.codec != null)
                _buildInfoRow('Codec', widget.result.codec!),
              if (widget.result.bitrate != null)
                _buildInfoRow('Bitrate', '${widget.result.bitrate! ~/ 1000} kbps'),
              if (widget.result.sampleRate != null)
                _buildInfoRow('Sample Rate', '${widget.result.sampleRate} Hz'),
              if (widget.result.duration != null)
                _buildInfoRow('Duration', _formatDuration(widget.result.duration!)),
            ],
          ),

          // Silence intervals
          if (widget.result.silenceIntervals.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildSection(
              title: 'Silence Intervals (${widget.result.silenceIntervals.length})',
              children: widget.result.silenceIntervals
                  .take(20)
                  .map((s) => _buildInfoRow(
                        'Interval',
                        s.toString(),
                        icon: Icons.volume_off,
                      ))
                  .toList(),
            ),
            if (widget.result.silenceIntervals.length > 20)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '... and ${widget.result.silenceIntervals.length - 20} more',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],

          // Chapters
          if (widget.result.chapters.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildSection(
              title: 'Chapters (${widget.result.chapters.length})',
              children: widget.result.chapters
                  .take(20)
                  .map((c) => _buildInfoRow(
                        'Ch ${c.index + 1}',
                        c.title,
                        icon: Icons.bookmark,
                      ))
                  .toList(),
            ),
            if (widget.result.chapters.length > 20)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '... and ${widget.result.chapters.length - 20} more',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],

          // Chapter silence details
          if (widget.result.chapterSilenceDetails.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildSection(
              title: 'Chapter Silence Issues',
              children: widget.result.chapterSilenceDetails
                  .map((cs) => _buildInfoRow(
                        'Issue',
                        cs.toString(),
                        icon: Icons.warning_amber,
                        color: Colors.amber,
                      ))
                  .toList(),
            ),
          ],

          // Error details
          if (widget.result.error != null) ...[
            const SizedBox(height: 16),
            _buildSection(
              title: 'Error Details',
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    widget.result.error!,
                    style: TextStyle(color: colorScheme.onErrorContainer),
                  ),
                ),
              ],
            ),
          ],

          // Waveform preview
          const SizedBox(height: 16),
          _buildSection(
            title: 'Waveform Preview',
            children: [
              if (_waveformPath != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(_waveformPath!),
                    fit: BoxFit.fitWidth,
                    errorBuilder: (context, error, stackTrace) => const Text('Failed to load waveform'),
                  ),
                )
              else if (_isGeneratingWaveform)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                )
              else
                Center(
                  child: OutlinedButton.icon(
                    onPressed: _generateWaveform,
                    icon: const Icon(Icons.waves),
                    label: const Text('Generate Waveform'),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(ColorScheme colorScheme) {
    Color backgroundColor;
    Color foregroundColor;

    switch (widget.result.status) {
      case ScanResultStatus.ok:
        backgroundColor = Colors.green.withAlpha(30);
        foregroundColor = Colors.green;
      case ScanResultStatus.missingAudio:
        backgroundColor = Colors.orange.withAlpha(30);
        foregroundColor = Colors.orange;
      case ScanResultStatus.corrupt:
        backgroundColor = Colors.red.withAlpha(30);
        foregroundColor = Colors.red;
      case ScanResultStatus.truncated:
        backgroundColor = Colors.deepOrange.withAlpha(30);
        foregroundColor = Colors.deepOrange;
      case ScanResultStatus.silence:
        backgroundColor = Colors.amber.withAlpha(30);
        foregroundColor = Colors.amber.shade700;
      case ScanResultStatus.chapterSilence:
        backgroundColor = Colors.purple.withAlpha(30);
        foregroundColor = Colors.purple;
      case ScanResultStatus.error:
        backgroundColor = colorScheme.errorContainer;
        foregroundColor = colorScheme.error;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(_getStatusIcon(), color: foregroundColor, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.result.status.name.toUpperCase(),
                  style: TextStyle(
                    color: foregroundColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  widget.result.statusDescription,
                  style: TextStyle(color: foregroundColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _getStatusIcon() {
    switch (widget.result.status) {
      case ScanResultStatus.ok:
        return Icons.check_circle;
      case ScanResultStatus.missingAudio:
        return Icons.warning;
      case ScanResultStatus.corrupt:
        return Icons.error;
      case ScanResultStatus.truncated:
        return Icons.content_cut;
      case ScanResultStatus.silence:
        return Icons.volume_off;
      case ScanResultStatus.chapterSilence:
        return Icons.bookmark_border;
      case ScanResultStatus.error:
        return Icons.error_outline;
    }
  }

  Widget _buildSection({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }

  Widget _buildInfoRow(
    String label,
    String value, {
    IconData? icon,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: color ?? Theme.of(context).colorScheme.outline),
            const SizedBox(width: 8),
          ],
          SizedBox(
            width: icon != null ? 60 : 80,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final mins = duration.inMinutes.remainder(60);
    final secs = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }
}
