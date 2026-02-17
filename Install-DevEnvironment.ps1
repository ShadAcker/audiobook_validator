<#
.SYNOPSIS
    Installs all prerequisites for building Audiobook Validator from source.

.DESCRIPTION
    This script automates the setup of the development environment for Audiobook Validator:
    - Enables Windows Developer Mode (required for Flutter desktop)
    - Installs Flutter SDK via winget
    - Installs FFmpeg via winget (with fallback to manual download)
    - Installs Visual Studio Build Tools (C++ workload for Windows desktop)
    - Configures environment variables
    - Validates the installation with flutter doctor

.PARAMETER SkipDeveloperMode
    Skip enabling Windows Developer Mode (if already enabled)

.PARAMETER SkipVisualStudio
    Skip Visual Studio installation (if already installed)

.PARAMETER SkipFFmpeg
    Skip FFmpeg installation (if already installed)

.PARAMETER SkipFlutter
    Skip Flutter installation (if already installed)

.PARAMETER FFmpegPath
    Custom path to install FFmpeg (default: C:\ffmpeg)

.EXAMPLE
    .\Install-DevEnvironment.ps1
    Full installation with all components.

.EXAMPLE
    .\Install-DevEnvironment.ps1 -SkipVisualStudio -SkipDeveloperMode
    Install only Flutter and FFmpeg.

.NOTES
    Author: Audiobook Validator Project
    Requires: Windows 10/11, PowerShell 5.1+, Administrator privileges
#>

[CmdletBinding()]
param(
    [switch]$SkipDeveloperMode,
    [switch]$SkipVisualStudio,
    [switch]$SkipFFmpeg,
    [switch]$SkipFlutter,
    [string]$FFmpegPath = "C:\ffmpeg"
)

#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region Helper Functions

function Write-Header {
    param([string]$Message)
    Write-Host ""
    Write-Host "=" * 70 -ForegroundColor Cyan
    Write-Host "  $Message" -ForegroundColor Cyan
    Write-Host "=" * 70 -ForegroundColor Cyan
}

function Write-Step {
    param([string]$Message)
    Write-Host "[*] $Message" -ForegroundColor Yellow
}

function Write-Success {
    param([string]$Message)
    Write-Host "[+] $Message" -ForegroundColor Green
}

function Write-Skipped {
    param([string]$Message)
    Write-Host "[-] $Message" -ForegroundColor DarkGray
}

function Write-Warning2 {
    param([string]$Message)
    Write-Host "[!] $Message" -ForegroundColor Magenta
}

function Write-ErrorMessage {
    param([string]$Message)
    Write-Host "[X] $Message" -ForegroundColor Red
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-CommandExists {
    param([string]$Command)
    $null = Get-Command $Command -ErrorAction SilentlyContinue
    return $?
}

function Add-ToPath {
    param(
        [string]$Path,
        [ValidateSet('User', 'Machine')]
        [string]$Scope = 'User'
    )
    
    $currentPath = [Environment]::GetEnvironmentVariable('PATH', $Scope)
    if ($currentPath -notlike "*$Path*") {
        $newPath = "$currentPath;$Path"
        [Environment]::SetEnvironmentVariable('PATH', $newPath, $Scope)
        $env:PATH = "$env:PATH;$Path"
        Write-Success "Added '$Path' to $Scope PATH"
        return $true
    }
    return $false
}

function Refresh-EnvironmentVariables {
    Write-Step "Refreshing environment variables..."
    
    # Refresh PATH from registry
    $machinePath = [Environment]::GetEnvironmentVariable('PATH', 'Machine')
    $userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
    $env:PATH = "$machinePath;$userPath"
    
    # Also refresh other common variables
    foreach ($level in @('Machine', 'User')) {
        $vars = [Environment]::GetEnvironmentVariables($level)
        foreach ($key in $vars.Keys) {
            if ($key -ne 'PATH') {
                Set-Item -Path "Env:$key" -Value $vars[$key] -ErrorAction SilentlyContinue
            }
        }
    }
}

#endregion

#region Installation Functions

function Enable-DeveloperMode {
    Write-Header "ENABLING DEVELOPER MODE"
    
    if ($SkipDeveloperMode) {
        Write-Skipped "Skipping Developer Mode (user requested)"
        return
    }
    
    # Check current state
    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock"
    $currentValue = Get-ItemProperty -Path $regPath -Name "AllowDevelopmentWithoutDevLicense" -ErrorAction SilentlyContinue
    
    if ($currentValue.AllowDevelopmentWithoutDevLicense -eq 1) {
        Write-Success "Developer Mode is already enabled"
        return
    }
    
    if (-not (Test-Administrator)) {
        Write-Warning2 "Administrator privileges required to enable Developer Mode"
        Write-Warning2 "Please enable manually: Settings > Privacy & Security > For Developers > Developer Mode"
        return
    }
    
    Write-Step "Enabling Developer Mode via registry..."
    
    try {
        if (-not (Test-Path $regPath)) {
            New-Item -Path $regPath -Force | Out-Null
        }
        Set-ItemProperty -Path $regPath -Name "AllowDevelopmentWithoutDevLicense" -Value 1 -Type DWord
        Write-Success "Developer Mode enabled successfully"
    }
    catch {
        Write-ErrorMessage "Failed to enable Developer Mode: $_"
        Write-Warning2 "Please enable manually: Settings > Privacy & Security > For Developers > Developer Mode"
    }
}

function Install-Flutter {
    Write-Header "INSTALLING FLUTTER SDK"
    
    if ($SkipFlutter) {
        Write-Skipped "Skipping Flutter installation (user requested)"
        return
    }
    
    # Check if Flutter is already installed
    if (Test-CommandExists 'flutter') {
        $version = flutter --version 2>&1 | Select-Object -First 1
        Write-Success "Flutter is already installed: $version"
        return
    }
    
    # Check for winget
    if (-not (Test-CommandExists 'winget')) {
        Write-ErrorMessage "winget is not available. Please install Flutter manually from:"
        Write-ErrorMessage "https://docs.flutter.dev/get-started/install/windows"
        return
    }
    
    Write-Step "Installing Flutter SDK via winget..."
    
    try {
        winget install --id=Google.FlutterSDK -e --accept-package-agreements --accept-source-agreements
        
        # Flutter via winget typically installs to user profile
        $possiblePaths = @(
            "$env:LOCALAPPDATA\Programs\flutter\bin",
            "$env:USERPROFILE\flutter\bin",
            "C:\flutter\bin"
        )
        
        foreach ($path in $possiblePaths) {
            if (Test-Path $path) {
                Add-ToPath -Path $path -Scope 'User'
                break
            }
        }
        
        Refresh-EnvironmentVariables
        
        if (Test-CommandExists 'flutter') {
            Write-Success "Flutter installed successfully"
        }
        else {
            Write-Warning2 "Flutter installed but not in PATH. You may need to restart your terminal."
        }
    }
    catch {
        Write-ErrorMessage "Failed to install Flutter: $_"
        Write-Warning2 "Please install manually from: https://docs.flutter.dev/get-started/install/windows"
    }
}

function Install-FFmpeg {
    Write-Header "INSTALLING FFMPEG"
    
    if ($SkipFFmpeg) {
        Write-Skipped "Skipping FFmpeg installation (user requested)"
        return
    }
    
    # Check if FFmpeg is already in PATH
    if (Test-CommandExists 'ffmpeg') {
        $version = ffmpeg -version 2>&1 | Select-Object -First 1
        Write-Success "FFmpeg is already installed: $version"
        return
    }
    
    # Check common locations
    $commonPaths = @(
        "$FFmpegPath\bin\ffmpeg.exe",
        "C:\ProgramData\chocolatey\bin\ffmpeg.exe",
        "$env:USERPROFILE\scoop\shims\ffmpeg.exe"
    )
    
    foreach ($path in $commonPaths) {
        if (Test-Path $path) {
            $binDir = Split-Path $path -Parent
            Add-ToPath -Path $binDir -Scope 'User'
            Write-Success "FFmpeg found at: $path"
            return
        }
    }
    
    # Try winget first
    if (Test-CommandExists 'winget') {
        Write-Step "Attempting to install FFmpeg via winget..."
        
        try {
            winget install --id=Gyan.FFmpeg -e --accept-package-agreements --accept-source-agreements
            Refresh-EnvironmentVariables
            
            if (Test-CommandExists 'ffmpeg') {
                Write-Success "FFmpeg installed via winget"
                return
            }
        }
        catch {
            Write-Warning2 "winget installation failed, falling back to manual download..."
        }
    }
    
    # Manual download fallback
    Write-Step "Downloading FFmpeg manually..."
    
    $downloadUrl = "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip"
    $tempZip = Join-Path $env:TEMP "ffmpeg-download.zip"
    $tempExtract = Join-Path $env:TEMP "ffmpeg-extract"
    
    try {
        # Download
        Write-Step "Downloading from $downloadUrl..."
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($downloadUrl, $tempZip)
        
        Write-Step "Extracting to $FFmpegPath..."
        
        # Clean up existing
        if (Test-Path $tempExtract) {
            Remove-Item $tempExtract -Recurse -Force
        }
        
        # Extract
        Expand-Archive -Path $tempZip -DestinationPath $tempExtract -Force
        
        # Find the extracted folder (it has version in name)
        $extractedFolder = Get-ChildItem $tempExtract -Directory | Select-Object -First 1
        
        if (-not $extractedFolder) {
            throw "Failed to find extracted FFmpeg folder"
        }
        
        # Create target directory
        if (Test-Path $FFmpegPath) {
            Write-Step "Removing existing FFmpeg installation..."
            Remove-Item $FFmpegPath -Recurse -Force
        }
        
        # Move to final location
        Move-Item -Path $extractedFolder.FullName -Destination $FFmpegPath
        
        # Add to PATH
        $ffmpegBin = Join-Path $FFmpegPath "bin"
        Add-ToPath -Path $ffmpegBin -Scope 'User'
        
        # Cleanup
        Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
        Remove-Item $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
        
        Refresh-EnvironmentVariables
        
        if (Test-CommandExists 'ffmpeg') {
            Write-Success "FFmpeg installed successfully to $FFmpegPath"
        }
        else {
            Write-Success "FFmpeg extracted to $FFmpegPath"
            Write-Warning2 "You may need to restart your terminal for PATH changes to take effect"
        }
    }
    catch {
        Write-ErrorMessage "Failed to download/install FFmpeg: $_"
        Write-Warning2 "Please download manually from: https://ffmpeg.org/download.html"
        Write-Warning2 "Extract to $FFmpegPath and add '$FFmpegPath\bin' to your PATH"
    }
}

function Install-VisualStudio {
    Write-Header "INSTALLING VISUAL STUDIO BUILD TOOLS"
    
    if ($SkipVisualStudio) {
        Write-Skipped "Skipping Visual Studio installation (user requested)"
        return
    }
    
    # Check if Visual Studio is already installed
    $vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    
    if (Test-Path $vsWhere) {
        $vsInstalls = & $vsWhere -all -format json | ConvertFrom-Json
        
        foreach ($install in $vsInstalls) {
            $installedComponents = & $vsWhere -path $install.installationPath -format json -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 | ConvertFrom-Json
            
            if ($installedComponents) {
                Write-Success "Visual Studio with C++ tools is already installed:"
                Write-Success "  $($install.displayName) - $($install.installationPath)"
                return
            }
        }
    }
    
    # Check if winget is available
    if (-not (Test-CommandExists 'winget')) {
        Write-Warning2 "winget not available. Please install Visual Studio manually:"
        Write-Warning2 "1. Download from: https://visualstudio.microsoft.com/downloads/"
        Write-Warning2 "2. Select 'Desktop development with C++' workload"
        return
    }
    
    Write-Step "Installing Visual Studio Community with C++ workload..."
    Write-Warning2 "This may take 10-30 minutes depending on your internet connection..."
    
    try {
        winget install Microsoft.VisualStudio.2022.Community --override "--add Microsoft.VisualStudio.Workload.NativeDesktop --includeRecommended --passive --wait" --accept-package-agreements --accept-source-agreements
        Write-Success "Visual Studio installed successfully"
    }
    catch {
        Write-ErrorMessage "Visual Studio installation failed: $_"
        Write-Warning2 "Please install manually from: https://visualstudio.microsoft.com/downloads/"
        Write-Warning2 "Select 'Desktop development with C++' workload during installation"
    }
}

function Test-FlutterDoctor {
    Write-Header "VERIFYING INSTALLATION"
    
    Refresh-EnvironmentVariables
    
    if (-not (Test-CommandExists 'flutter')) {
        Write-Warning2 "Flutter not found in PATH. Please restart your terminal and run 'flutter doctor'"
        return
    }
    
    Write-Step "Running flutter doctor..."
    Write-Host ""
    
    flutter doctor
    
    Write-Host ""
    Write-Success "Setup verification complete!"
    Write-Host ""
    Write-Host "If you see any issues above, please resolve them before continuing." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "NEXT STEPS:" -ForegroundColor Cyan
    Write-Host "  1. Restart your terminal (or open a new one)" -ForegroundColor White
    Write-Host "  2. Navigate to the audiobook_validator directory" -ForegroundColor White
    Write-Host "  3. Run: flutter pub get" -ForegroundColor White
    Write-Host "  4. Run: flutter run -d windows" -ForegroundColor White
}

#endregion

#region Main Script

Write-Host ""
Write-Host @"
    _             _ _       _                 _      __     __    _ _     _       _             
   / \  _   _  __| (_) ___ | |__   ___   ___ | | __  \ \   / /_ _| (_) __| | __ _| |_ ___  _ __ 
  / _ \| | | |/ _` | |/ _ \| '_ \ / _ \ / _ \| |/ /   \ \ / / _` | | |/ _` |/ _` | __/ _ \| '__|
 / ___ \ |_| | (_| | | (_) | |_) | (_) | (_) |   <     \ V / (_| | | | (_| | (_| | || (_) | |   
/_/   \_\__,_|\__,_|_|\___/|_.__/ \___/ \___/|_|\_\     \_/ \__,_|_|_|\__,_|\__,_|\__\___/|_|   
                                                                                                
"@ -ForegroundColor Magenta

Write-Host "Development Environment Setup Script" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""

# Check Windows version
$osVersion = [Environment]::OSVersion.Version
if ($osVersion.Major -lt 10) {
    Write-ErrorMessage "This script requires Windows 10 or later"
    exit 1
}

# Administrator check
if (-not (Test-Administrator)) {
    Write-Warning2 "Running without Administrator privileges"
    Write-Warning2 "Some features (like Developer Mode) may require manual configuration"
    Write-Host ""
    $response = Read-Host "Continue anyway? (Y/n)"
    if ($response -eq 'n' -or $response -eq 'N') {
        Write-Host "Please run this script as Administrator for full functionality"
        exit 0
    }
}

# Run installation steps
try {
    Enable-DeveloperMode
    Install-VisualStudio
    Install-FFmpeg
    Install-Flutter
    Test-FlutterDoctor
}
catch {
    Write-ErrorMessage "An unexpected error occurred: $_"
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
    exit 1
}

Write-Host ""
Write-Host "Script completed!" -ForegroundColor Green
Write-Host ""

#endregion
