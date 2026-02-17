import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/logging_service.dart';

class LogsPage extends StatelessWidget {
  const LogsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final logger = context.watch<LoggingService>();

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            border: Border(
              bottom: BorderSide(color: colorScheme.outline.withAlpha(50)),
            ),
          ),
          child: Row(
            children: [
              Text(
                'Application Logs',
                style: theme.textTheme.titleLarge,
              ),
              const Spacer(),
              Text(
                '${logger.logs.length} entries',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.outline,
                ),
              ),
              const SizedBox(width: 16),
              OutlinedButton.icon(
                onPressed: () async {
                  final outputPath = await FilePicker.platform.saveFile(
                    dialogTitle: 'Export Logs',
                    fileName: 'audiobook_validator_logs.txt',
                    type: FileType.custom,
                    allowedExtensions: ['txt', 'log'],
                  );
                  if (outputPath != null) {
                    final result = await logger.exportLogs(outputPath);
                    if (result != null && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Logs exported to: $result')),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.download),
                label: const Text('Export'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Clear Logs'),
                      content: const Text('Clear all in-memory logs?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () {
                            logger.clearLogs();
                            Navigator.pop(context);
                          },
                          child: const Text('Clear'),
                        ),
                      ],
                    ),
                  );
                },
                icon: const Icon(Icons.delete_outline),
                label: const Text('Clear'),
              ),
            ],
          ),
        ),
        // Logs list
        Expanded(
          child: logger.logs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.description_outlined,
                        size: 64,
                        color: colorScheme.outline,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No logs yet',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: logger.logs.length,
                  itemBuilder: (context, index) {
                    // Show newest first
                    final log = logger.logs[logger.logs.length - 1 - index];
                    return _LogEntryTile(entry: log);
                  },
                ),
        ),
        // Footer with log file path
        if (logger.logFilePath != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              border: Border(
                top: BorderSide(color: colorScheme.outline.withAlpha(50)),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.folder_outlined, size: 16, color: colorScheme.outline),
                const SizedBox(width: 8),
                Expanded(
                  child: SelectableText(
                    'Log file: ${logger.logFilePath}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.outline,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _LogEntryTile extends StatelessWidget {
  final LogEntry entry;

  const _LogEntryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    Color levelColor;
    IconData levelIcon;

    switch (entry.level) {
      case LogLevel.debug:
        levelColor = colorScheme.outline;
        levelIcon = Icons.bug_report;
      case LogLevel.info:
        levelColor = Colors.blue;
        levelIcon = Icons.info_outline;
      case LogLevel.warning:
        levelColor = Colors.orange;
        levelIcon = Icons.warning_amber;
      case LogLevel.error:
        levelColor = colorScheme.error;
        levelIcon = Icons.error_outline;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colorScheme.outline.withAlpha(20)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(levelIcon, size: 16, color: levelColor),
          const SizedBox(width: 8),
          SizedBox(
            width: 60,
            child: Text(
              entry.levelString,
              style: theme.textTheme.bodySmall?.copyWith(
                color: levelColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SizedBox(
            width: 160,
            child: Text(
              entry.formattedTimestamp,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.outline,
                fontFamily: 'monospace',
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              entry.message,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
