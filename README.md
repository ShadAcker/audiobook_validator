# Audiobook Validator

A cross-platform desktop application for validating audiobook files using FFmpeg. Quickly scan your audiobook collection to detect corrupted files, truncated audio, excessive silence, and chapter issues.

![License](https://img.shields.io/badge/license-AGPL--3.0-blue.svg)
![Flutter](https://img.shields.io/badge/Flutter-3.41+-02569B.svg)
![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux-lightgrey.svg)

## Features

- **Corruption Detection** - Scans audio streams for decoding errors and data corruption
- **Truncation Check** - Identifies files with incomplete or cut-off audio data
- **Silence Detection** - Finds unusually long silent sections that may indicate issues
- **Chapter Analysis** - Validates chapter markers and timing in supported formats
- **Drag & Drop** - Simply drag folders or files onto the app to scan
- **Export Results** - Export scan results to CSV for further analysis
- **Progress Tracking** - Real-time progress with detailed status for each file
- **Configurable Settings** - Adjust silence thresholds, scan modes, and FFmpeg paths

### Supported Audio Formats

- MP3 (`.mp3`)
- M4B Audiobook (`.m4b`)
- M4A (`.m4a`)
- AAC (`.aac`)
- WAV (`.wav`)
- FLAC (`.flac`)
- OGG (`.ogg`)

## Prerequisites

Before building and running this application, you need to install the following:

### 1. Flutter SDK

Flutter is required to build and run this application.

#### Windows

**Option A: Using winget (Recommended)**
```powershell
winget install --id=Google.FlutterSDK -e
```

**Option B: Manual Installation**
1. Download Flutter SDK from https://docs.flutter.dev/get-started/install/windows
2. Extract to a location (e.g., `C:\dev\flutter`)
3. Add `C:\dev\flutter\bin` to your system PATH

#### macOS
```bash
brew install --cask flutter
```

#### Linux
```bash
sudo snap install flutter --classic
```

### 2. FFmpeg

FFmpeg is required for audio analysis.

#### Windows

**Option A: Using winget**
```powershell
winget install --id=Gyan.FFmpeg -e
```

**Option B: Using Chocolatey**
```powershell
choco install ffmpeg -y
```

**Option C: Manual Installation**
1. Download from https://ffmpeg.org/download.html
2. Extract and add the `bin` folder to your system PATH

#### macOS
```bash
brew install ffmpeg
```

#### Linux
```bash
sudo apt install ffmpeg    # Debian/Ubuntu
sudo dnf install ffmpeg    # Fedora
sudo pacman -S ffmpeg      # Arch
```

### 3. Platform-Specific Requirements

#### Windows

Visual Studio with C++ build tools is required for Windows desktop development.

**Using winget:**
```powershell
winget install Microsoft.VisualStudio.2022.Community --override "--add Microsoft.VisualStudio.Workload.NativeDesktop --includeRecommended --passive"
```

**Using Chocolatey:**
```powershell
choco install visualstudio2022community visualstudio2022-workload-nativedesktop -y
```

**Manual Installation:**
1. Download [Visual Studio Community](https://visualstudio.microsoft.com/downloads/)
2. During installation, select **"Desktop development with C++"** workload
3. Ensure all default components are selected

#### macOS

Xcode is required:
```bash
xcode-select --install
```

#### Linux

Required packages for Linux desktop:
```bash
# Debian/Ubuntu
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev

# Fedora
sudo dnf install clang cmake ninja-build gtk3-devel

# Arch
sudo pacman -S clang cmake ninja gtk3
```

## Verify Your Setup

After installing the prerequisites, verify everything is configured correctly:

```bash
flutter doctor
```

You should see checkmarks for:
- Flutter
- Your target platform (Windows/macOS/Linux)

**Note:** You can ignore Android/iOS/Chrome warnings if you only plan to build desktop apps.

### Common Issues

**Chrome not found:**
If you see a Chrome warning but want to use Edge, set this environment variable:
```powershell
# Windows PowerShell
[System.Environment]::SetEnvironmentVariable("CHROME_EXECUTABLE", "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe", "User")
```

**FFmpeg not found:**
The app will try to auto-detect FFmpeg. If it fails, you can manually configure the path in Settings after launching the app.

## Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/YOUR_USERNAME/audiobook_validator.git
   cd audiobook_validator
   ```

2. **Install Flutter dependencies:**
   ```bash
   flutter pub get
   ```

3. **Run the application:**
   ```bash
   # Windows
   flutter run -d windows

   # macOS
   flutter run -d macos

   # Linux
   flutter run -d linux
   ```

## Building for Release

To create a release build:

```bash
# Windows
flutter build windows --release

# macOS
flutter build macos --release

# Linux
flutter build linux --release
```

The compiled application will be in:
- Windows: `build/windows/x64/runner/Release/`
- macOS: `build/macos/Build/Products/Release/`
- Linux: `build/linux/x64/release/bundle/`

## Usage

1. **Launch the application**
2. **Scan files** using one of these methods:
   - Click "Select Folder" to choose a directory
   - Click "Select Files" to pick individual files
   - Drag and drop files/folders onto the app window
3. **Review results** - Files are color-coded:
   - ✅ Green: No issues found
   - ⚠️ Yellow: Warnings (e.g., unusual silence)
   - ❌ Red: Errors detected (corruption, truncation)
4. **Export results** to CSV for record-keeping or further analysis
5. **Configure settings** to adjust:
   - Silence detection threshold (dB)
   - Minimum silence duration (seconds)
   - Scan mode (full vs. sample)
   - Custom FFmpeg/FFprobe paths

## Project Structure

```
lib/
├── main.dart                 # Application entry point
├── models/
│   └── scan_result.dart      # Data models for scan results
├── services/
│   ├── audio_scanner_service.dart   # FFmpeg scanning logic
│   ├── logging_service.dart         # Application logging
│   ├── settings_provider.dart       # User preferences
│   └── waveform_service.dart        # Audio waveform generation
└── ui/
    ├── scanner_page.dart     # Main scanning interface
    ├── settings_page.dart    # Settings configuration
    ├── logs_page.dart        # Log viewer
    ├── about_page.dart       # About information
    └── widgets/              # Reusable UI components
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## License

This project is licensed under the **GNU Affero General Public License v3.0** - see the [LICENSE](LICENSE) file for details.

This means:
- ✅ You can use, modify, and distribute this software
- ✅ You can use it for commercial purposes
- ⚠️ You must disclose your source code if you distribute modified versions
- ⚠️ You must use the same license for derivative works
- ⚠️ If you run a modified version on a server, you must make the source available to users

## Acknowledgments

- [FFmpeg](https://ffmpeg.org/) - The backbone of audio analysis
- [Flutter](https://flutter.dev/) - Cross-platform UI framework
- [Provider](https://pub.dev/packages/provider) - State management
