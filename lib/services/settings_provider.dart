import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Application settings provider
class SettingsProvider extends ChangeNotifier {
  // Default values
  double _silenceThresholdDb = -50.0;
  double _silenceDurationSec = 10.0;
  String _codec = 'aac';
  int _bitrate = 128;
  bool _detectChapterSilence = true;
  ThemeMode _themeMode = ThemeMode.system;
  String? _ffmpegPath;
  String? _ffprobePath;
  String _scanMode = 'sample'; // 'sample' or 'full'

  // Getters
  double get silenceThresholdDb => _silenceThresholdDb;
  double get silenceDurationSec => _silenceDurationSec;
  String get codec => _codec;
  int get bitrate => _bitrate;
  bool get detectChapterSilence => _detectChapterSilence;
  ThemeMode get themeMode => _themeMode;
  String? get ffmpegPath => _ffmpegPath;
  String? get ffprobePath => _ffprobePath;
  String get scanMode => _scanMode;

  // Setters with persistence
  set silenceThresholdDb(double value) {
    _silenceThresholdDb = value;
    _save('silenceThresholdDb', value);
    notifyListeners();
  }

  set silenceDurationSec(double value) {
    _silenceDurationSec = value;
    _save('silenceDurationSec', value);
    notifyListeners();
  }

  set codec(String value) {
    _codec = value;
    _save('codec', value);
    notifyListeners();
  }

  set bitrate(int value) {
    _bitrate = value;
    _save('bitrate', value);
    notifyListeners();
  }

  set detectChapterSilence(bool value) {
    _detectChapterSilence = value;
    _save('detectChapterSilence', value);
    notifyListeners();
  }

  set themeMode(ThemeMode value) {
    _themeMode = value;
    _save('themeMode', value.index);
    notifyListeners();
  }

  set ffmpegPath(String? value) {
    _ffmpegPath = value;
    if (value != null) {
      _save('ffmpegPath', value);
    }
    notifyListeners();
  }

  set ffprobePath(String? value) {
    _ffprobePath = value;
    if (value != null) {
      _save('ffprobePath', value);
    }
    notifyListeners();
  }

  set scanMode(String value) {
    _scanMode = value;
    _save('scanMode', value);
    notifyListeners();
  }

  /// Load settings from shared preferences
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    
    _silenceThresholdDb = prefs.getDouble('silenceThresholdDb') ?? -50.0;
    _silenceDurationSec = prefs.getDouble('silenceDurationSec') ?? 10.0;
    _codec = prefs.getString('codec') ?? 'aac';
    _bitrate = prefs.getInt('bitrate') ?? 128;
    _detectChapterSilence = prefs.getBool('detectChapterSilence') ?? true;
    _ffmpegPath = prefs.getString('ffmpegPath');
    _ffprobePath = prefs.getString('ffprobePath');
    _scanMode = prefs.getString('scanMode') ?? 'sample';
    
    final themeModeIndex = prefs.getInt('themeMode') ?? 0;
    _themeMode = ThemeMode.values[themeModeIndex.clamp(0, ThemeMode.values.length - 1)];

    notifyListeners();
  }

  /// Save a single value
  Future<void> _save(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is double) {
      await prefs.setDouble(key, value);
    } else if (value is int) {
      await prefs.setInt(key, value);
    } else if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is String) {
      await prefs.setString(key, value);
    }
  }

  /// Reset to defaults
  void resetToDefaults() {
    silenceThresholdDb = -50.0;
    silenceDurationSec = 10.0;
    codec = 'aac';
    bitrate = 128;
    detectChapterSilence = true;
    themeMode = ThemeMode.system;
    scanMode = 'sample';
  }

  /// Available codecs for re-encoding
  static const List<String> availableCodecs = [
    'aac',
    'libmp3lame',
    'flac',
    'libopus',
    'libvorbis',
  ];

  /// Available bitrates for re-encoding
  static const List<int> availableBitrates = [
    64,
    96,
    128,
    192,
    256,
    320,
  ];

  /// Get codec display name
  static String codecDisplayName(String codec) {
    switch (codec) {
      case 'aac':
        return 'AAC';
      case 'libmp3lame':
        return 'MP3';
      case 'flac':
        return 'FLAC (lossless)';
      case 'libopus':
        return 'Opus';
      case 'libvorbis':
        return 'Vorbis (OGG)';
      default:
        return codec.toUpperCase();
    }
  }
}
