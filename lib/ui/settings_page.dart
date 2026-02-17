import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/settings_provider.dart';
import '../services/waveform_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final WaveformService _waveformService = WaveformService();
  int _cacheSize = 0;

  @override
  void initState() {
    super.initState();
    _loadCacheSize();
  }

  Future<void> _loadCacheSize() async {
    final size = await _waveformService.getCacheSize();
    if (mounted) {
      setState(() => _cacheSize = size);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = context.watch<SettingsProvider>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Settings', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 24),

          // Theme section
          _buildSectionHeader('Appearance'),
          _buildCard([
            ListTile(
              title: const Text('Theme'),
              subtitle: const Text('Choose light, dark, or system theme'),
              trailing: SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.light,
                    icon: Icon(Icons.light_mode),
                    label: Text('Light'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.system,
                    icon: Icon(Icons.settings_suggest),
                    label: Text('System'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    icon: Icon(Icons.dark_mode),
                    label: Text('Dark'),
                  ),
                ],
                selected: {settings.themeMode},
                onSelectionChanged: (selected) {
                  settings.themeMode = selected.first;
                },
              ),
            ),
          ]),
          const SizedBox(height: 24),

          // Detection settings
          _buildSectionHeader('Silence Detection'),
          _buildCard([
            ListTile(
              title: const Text('Silence Threshold'),
              subtitle: Text('${settings.silenceThresholdDb.toStringAsFixed(0)} dB'),
              trailing: SizedBox(
                width: 200,
                child: Slider(
                  value: settings.silenceThresholdDb,
                  min: -70,
                  max: -20,
                  divisions: 50,
                  label: '${settings.silenceThresholdDb.toStringAsFixed(0)} dB',
                  onChanged: (value) {
                    settings.silenceThresholdDb = value;
                  },
                ),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              title: const Text('Minimum Silence Duration'),
              subtitle: Text('${settings.silenceDurationSec.toStringAsFixed(0)} seconds'),
              trailing: SizedBox(
                width: 200,
                child: Slider(
                  value: settings.silenceDurationSec,
                  min: 1,
                  max: 60,
                  divisions: 59,
                  label: '${settings.silenceDurationSec.toStringAsFixed(0)}s',
                  onChanged: (value) {
                    settings.silenceDurationSec = value;
                  },
                ),
              ),
            ),
            const Divider(height: 1),
            SwitchListTile(
              title: const Text('Detect Chapter-Level Silence'),
              subtitle: const Text('Check for silence after chapter boundaries'),
              value: settings.detectChapterSilence,
              onChanged: (value) {
                settings.detectChapterSilence = value;
              },
            ),
            const Divider(height: 1),
            ListTile(
              title: const Text('Scan Mode'),
              subtitle: Text(settings.scanMode == 'sample' 
                  ? 'Sample (Fast) - Checks segments at intervals' 
                  : 'Full (Thorough) - Scans entire file'),
              trailing: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'sample',
                    icon: Icon(Icons.speed),
                    label: Text('Sample'),
                  ),
                  ButtonSegment(
                    value: 'full',
                    icon: Icon(Icons.search),
                    label: Text('Full'),
                  ),
                ],
                selected: {settings.scanMode},
                onSelectionChanged: (selected) {
                  settings.scanMode = selected.first;
                },
              ),
            ),
          ]),
          const SizedBox(height: 24),

          // Re-encoding settings
          _buildSectionHeader('Re-encoding'),
          _buildCard([
            ListTile(
              title: const Text('Output Codec'),
              subtitle: Text(SettingsProvider.codecDisplayName(settings.codec)),
              trailing: DropdownButton<String>(
                value: settings.codec,
                items: SettingsProvider.availableCodecs.map((codec) {
                  return DropdownMenuItem(
                    value: codec,
                    child: Text(SettingsProvider.codecDisplayName(codec)),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) settings.codec = value;
                },
              ),
            ),
            const Divider(height: 1),
            ListTile(
              title: const Text('Output Bitrate'),
              subtitle: Text('${settings.bitrate} kbps'),
              trailing: DropdownButton<int>(
                value: settings.bitrate,
                items: SettingsProvider.availableBitrates.map((bitrate) {
                  return DropdownMenuItem(
                    value: bitrate,
                    child: Text('$bitrate kbps'),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) settings.bitrate = value;
                },
              ),
            ),
          ]),
          const SizedBox(height: 24),

          // FFmpeg paths
          _buildSectionHeader('FFmpeg Configuration'),
          _buildCard([
            ListTile(
              title: const Text('FFmpeg Path'),
              subtitle: Text(settings.ffmpegPath ?? 'Using system PATH'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (settings.ffmpegPath != null)
                    IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        settings.ffmpegPath = null;
                      },
                    ),
                  TextButton(
                    onPressed: () async {
                      final result = await FilePicker.platform.pickFiles(
                        dialogTitle: 'Select ffmpeg executable',
                        type: FileType.any,
                      );
                      if (result != null && result.files.isNotEmpty) {
                        settings.ffmpegPath = result.files.first.path;
                      }
                    },
                    child: const Text('Browse'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              title: const Text('FFprobe Path'),
              subtitle: Text(settings.ffprobePath ?? 'Using system PATH'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (settings.ffprobePath != null)
                    IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        settings.ffprobePath = null;
                      },
                    ),
                  TextButton(
                    onPressed: () async {
                      final result = await FilePicker.platform.pickFiles(
                        dialogTitle: 'Select ffprobe executable',
                        type: FileType.any,
                      );
                      if (result != null && result.files.isNotEmpty) {
                        settings.ffprobePath = result.files.first.path;
                      }
                    },
                    child: const Text('Browse'),
                  ),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 24),

          // Cache settings
          _buildSectionHeader('Cache'),
          _buildCard([
            ListTile(
              title: const Text('Waveform Cache'),
              subtitle: Text('Size: ${WaveformService.formatBytes(_cacheSize)}'),
              trailing: TextButton(
                onPressed: () async {
                  await _waveformService.clearCache();
                  _loadCacheSize();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Cache cleared')),
                    );
                  }
                },
                child: const Text('Clear Cache'),
              ),
            ),
          ]),
          const SizedBox(height: 24),

          // Reset
          Center(
            child: OutlinedButton.icon(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Reset Settings'),
                    content: const Text('Reset all settings to defaults?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () {
                          settings.resetToDefaults();
                          Navigator.pop(context);
                        },
                        child: const Text('Reset'),
                      ),
                    ],
                  ),
                );
              },
              icon: const Icon(Icons.restore),
              label: const Text('Reset to Defaults'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outline.withAlpha(50),
        ),
      ),
      child: Column(children: children),
    );
  }
}
