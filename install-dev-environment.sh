#!/bin/bash
#
# Install Development Environment for Audiobook Validator
# 
# This script automates the setup of the development environment on macOS and Linux:
# - Installs Flutter SDK
# - Installs FFmpeg
# - Installs platform-specific build tools (Xcode CLI on macOS, build packages on Linux)
# - Validates the installation with flutter doctor
#
# Usage:
#   ./install-dev-environment.sh [OPTIONS]
#
# Options:
#   --skip-flutter    Skip Flutter installation
#   --skip-ffmpeg     Skip FFmpeg installation
#   --skip-tools      Skip build tools installation
#   --help            Show this help message
#
# Note: This script has NOT been tested by the original author (Windows user).
#       Contributions and bug reports are welcome!
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# Flags
SKIP_FLUTTER=false
SKIP_FFMPEG=false
SKIP_TOOLS=false

#region Helper Functions

print_header() {
    echo ""
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}======================================================================${NC}"
}

print_step() {
    echo -e "${YELLOW}[*] $1${NC}"
}

print_success() {
    echo -e "${GREEN}[+] $1${NC}"
}

print_skipped() {
    echo -e "${GRAY}[-] $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}[!] $1${NC}"
}

print_error() {
    echo -e "${RED}[X] $1${NC}"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

detect_os() {
    case "$(uname -s)" in
        Darwin*)    echo "macos";;
        Linux*)     echo "linux";;
        *)          echo "unknown";;
    esac
}

detect_linux_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$ID"
    elif [ -f /etc/debian_version ]; then
        echo "debian"
    elif [ -f /etc/redhat-release ]; then
        echo "rhel"
    else
        echo "unknown"
    fi
}

#endregion

#region Installation Functions

install_homebrew() {
    if ! command_exists brew; then
        print_step "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        
        # Add Homebrew to PATH for this session
        if [ -f /opt/homebrew/bin/brew ]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        elif [ -f /usr/local/bin/brew ]; then
            eval "$(/usr/local/bin/brew shellenv)"
        fi
        print_success "Homebrew installed"
    else
        print_success "Homebrew already installed"
    fi
}

install_ffmpeg_macos() {
    print_header "INSTALLING FFMPEG (macOS)"
    
    if $SKIP_FFMPEG; then
        print_skipped "Skipping FFmpeg (user requested)"
        return
    fi
    
    if command_exists ffmpeg; then
        print_success "FFmpeg already installed: $(ffmpeg -version | head -n1)"
        return
    fi
    
    install_homebrew
    print_step "Installing FFmpeg via Homebrew..."
    brew install ffmpeg
    print_success "FFmpeg installed"
}

install_ffmpeg_linux() {
    print_header "INSTALLING FFMPEG (Linux)"
    
    if $SKIP_FFMPEG; then
        print_skipped "Skipping FFmpeg (user requested)"
        return
    fi
    
    if command_exists ffmpeg; then
        print_success "FFmpeg already installed: $(ffmpeg -version | head -n1)"
        return
    fi
    
    local distro=$(detect_linux_distro)
    print_step "Installing FFmpeg for $distro..."
    
    case "$distro" in
        ubuntu|debian|pop|mint|elementary)
            sudo apt update
            sudo apt install -y ffmpeg
            ;;
        fedora)
            sudo dnf install -y ffmpeg
            ;;
        centos|rhel|rocky|alma)
            # Enable RPM Fusion for FFmpeg
            sudo dnf install -y epel-release
            sudo dnf install -y --enablerepo=powertools ffmpeg || \
            sudo dnf install -y ffmpeg
            ;;
        arch|manjaro|endeavouros)
            sudo pacman -Sy --noconfirm ffmpeg
            ;;
        opensuse*|suse*)
            sudo zypper install -y ffmpeg
            ;;
        *)
            print_warning "Unknown distribution: $distro"
            print_warning "Please install FFmpeg manually"
            return 1
            ;;
    esac
    
    print_success "FFmpeg installed"
}

install_flutter_macos() {
    print_header "INSTALLING FLUTTER (macOS)"
    
    if $SKIP_FLUTTER; then
        print_skipped "Skipping Flutter (user requested)"
        return
    fi
    
    if command_exists flutter; then
        print_success "Flutter already installed: $(flutter --version | head -n1)"
        return
    fi
    
    install_homebrew
    print_step "Installing Flutter via Homebrew..."
    brew install --cask flutter
    
    # Add to PATH if needed
    if [ -d "/opt/homebrew/Caskroom/flutter" ]; then
        export PATH="$PATH:/opt/homebrew/Caskroom/flutter/*/flutter/bin"
    fi
    
    print_success "Flutter installed"
}

install_flutter_linux() {
    print_header "INSTALLING FLUTTER (Linux)"
    
    if $SKIP_FLUTTER; then
        print_skipped "Skipping Flutter (user requested)"
        return
    fi
    
    if command_exists flutter; then
        print_success "Flutter already installed: $(flutter --version | head -n1)"
        return
    fi
    
    # Try snap first (works on most distros)
    if command_exists snap; then
        print_step "Installing Flutter via Snap..."
        sudo snap install flutter --classic
        print_success "Flutter installed via Snap"
        return
    fi
    
    # Manual installation fallback
    print_step "Installing Flutter manually..."
    local flutter_dir="$HOME/flutter"
    
    if [ ! -d "$flutter_dir" ]; then
        print_step "Downloading Flutter SDK..."
        cd "$HOME"
        git clone https://github.com/flutter/flutter.git -b stable --depth 1
    fi
    
    # Add to PATH
    export PATH="$PATH:$flutter_dir/bin"
    
    # Add to shell profile
    local shell_profile=""
    if [ -n "$ZSH_VERSION" ]; then
        shell_profile="$HOME/.zshrc"
    elif [ -n "$BASH_VERSION" ]; then
        shell_profile="$HOME/.bashrc"
    fi
    
    if [ -n "$shell_profile" ] && ! grep -q "flutter/bin" "$shell_profile" 2>/dev/null; then
        echo 'export PATH="$PATH:$HOME/flutter/bin"' >> "$shell_profile"
        print_success "Added Flutter to $shell_profile"
    fi
    
    print_success "Flutter installed to $flutter_dir"
}

install_build_tools_macos() {
    print_header "INSTALLING BUILD TOOLS (macOS)"
    
    if $SKIP_TOOLS; then
        print_skipped "Skipping build tools (user requested)"
        return
    fi
    
    # Check for Xcode CLI tools
    if xcode-select -p >/dev/null 2>&1; then
        print_success "Xcode Command Line Tools already installed"
    else
        print_step "Installing Xcode Command Line Tools..."
        xcode-select --install
        print_warning "Please complete the Xcode CLI installation popup, then re-run this script"
        exit 0
    fi
    
    # Accept Xcode license if needed
    if ! sudo xcodebuild -license check 2>/dev/null; then
        print_step "Accepting Xcode license..."
        sudo xcodebuild -license accept
    fi
    
    # Install CocoaPods for iOS/macOS
    if ! command_exists pod; then
        print_step "Installing CocoaPods..."
        sudo gem install cocoapods
        print_success "CocoaPods installed"
    else
        print_success "CocoaPods already installed"
    fi
}

install_build_tools_linux() {
    print_header "INSTALLING BUILD TOOLS (Linux)"
    
    if $SKIP_TOOLS; then
        print_skipped "Skipping build tools (user requested)"
        return
    fi
    
    local distro=$(detect_linux_distro)
    print_step "Installing build tools for $distro..."
    
    case "$distro" in
        ubuntu|debian|pop|mint|elementary)
            sudo apt update
            sudo apt install -y \
                clang \
                cmake \
                ninja-build \
                pkg-config \
                libgtk-3-dev \
                liblzma-dev \
                libstdc++-12-dev
            ;;
        fedora)
            sudo dnf install -y \
                clang \
                cmake \
                ninja-build \
                gtk3-devel \
                xz-devel
            ;;
        arch|manjaro|endeavouros)
            sudo pacman -Sy --noconfirm \
                clang \
                cmake \
                ninja \
                gtk3 \
                xz
            ;;
        opensuse*|suse*)
            sudo zypper install -y \
                clang \
                cmake \
                ninja \
                gtk3-devel \
                xz-devel
            ;;
        *)
            print_warning "Unknown distribution: $distro"
            print_warning "Please install: clang, cmake, ninja-build, gtk3-dev, liblzma-dev"
            return 1
            ;;
    esac
    
    print_success "Build tools installed"
}

run_flutter_doctor() {
    print_header "RUNNING FLUTTER DOCTOR"
    
    if ! command_exists flutter; then
        print_error "Flutter not found in PATH"
        print_warning "Please restart your terminal or run: source ~/.bashrc (or ~/.zshrc)"
        return 1
    fi
    
    print_step "Running flutter doctor..."
    flutter doctor
    
    print_step "Enabling desktop support..."
    local os=$(detect_os)
    case "$os" in
        macos)
            flutter config --enable-macos-desktop
            ;;
        linux)
            flutter config --enable-linux-desktop
            ;;
    esac
    
    print_success "Flutter configured for desktop development"
}

#endregion

#region Main

show_help() {
    echo "Install Development Environment for Audiobook Validator"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --skip-flutter    Skip Flutter installation"
    echo "  --skip-ffmpeg     Skip FFmpeg installation"
    echo "  --skip-tools      Skip build tools installation"
    echo "  --help            Show this help message"
    echo ""
    echo "Note: This script requires sudo for some operations."
}

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-flutter)
                SKIP_FLUTTER=true
                shift
                ;;
            --skip-ffmpeg)
                SKIP_FFMPEG=true
                shift
                ;;
            --skip-tools)
                SKIP_TOOLS=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    print_header "AUDIOBOOK VALIDATOR - DEV ENVIRONMENT SETUP"
    
    local os=$(detect_os)
    echo ""
    echo "Detected OS: $os"
    
    if [ "$os" = "unknown" ]; then
        print_error "Unsupported operating system"
        exit 1
    fi
    
    echo ""
    print_warning "NOTE: This script was created by a Windows user and has NOT been"
    print_warning "      thoroughly tested on $os. Please report any issues!"
    echo ""
    
    # Run installations based on OS
    case "$os" in
        macos)
            install_build_tools_macos
            install_ffmpeg_macos
            install_flutter_macos
            ;;
        linux)
            install_build_tools_linux
            install_ffmpeg_linux
            install_flutter_linux
            ;;
    esac
    
    run_flutter_doctor
    
    print_header "INSTALLATION COMPLETE"
    echo ""
    print_success "Development environment setup complete!"
    echo ""
    echo "Next steps:"
    echo "  1. Restart your terminal (or run: source ~/.bashrc)"
    echo "  2. Navigate to the project directory"
    echo "  3. Run: flutter pub get"
    echo "  4. Run: flutter run -d $([ "$os" = "macos" ] && echo "macos" || echo "linux")"
    echo ""
}

main "$@"
