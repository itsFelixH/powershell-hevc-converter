<div align="center">

[![Documentation](https://img.shields.io/badge/docs-GitHub%20Pages-blue?style=for-the-badge&logo=github)](https://itsfelixh.github.io/powershell-hevc-converter/)
![GitHub Discussions](https://img.shields.io/github/discussions/itsfelixh/powershell-hevc-converter?style=for-the-badge)
[![FFmpeg](https://img.shields.io/badge/FFmpeg-Required-green?style=for-the-badge&logo=ffmpeg)](https://ffmpeg.org/)

</div>

# 🎬 PowerShell HEVC Video Converter Script

## 🌟 Overview

This PowerShell script automates the conversion of various video formats to HEVC (H.265) using FFmpeg, optimizing for file size while maintaining excellent quality.

## ✨ Features

| 🎯 **Smart Conversion** | 📊 **Quality Analysis** | ⚡ **Performance** | 🛠️ **Advanced Tools** |
|:---:|:---:|:---:|:---:|
| Batch processing | VMAF/PSNR/SSIM metrics | Hardware acceleration | Preset profiles |
| Auto file detection | Compression analysis | Multi-threading | Settings optimization |
| Error handling | Quality validation | Progress tracking | Integrity verification |

### 🎬 **Core Capabilities**

- **🔄 Batch Conversion**: Process multiple video files with intelligent queuing
- **🎯 Smart Presets**: Content-aware encoding profiles (Animation, Film, ScreenCapture, etc.)
- **⚡ Hardware Acceleration**: NVENC, QSV, and VAAPI support for faster encoding
- **📊 Quality Metrics**: VMAF, PSNR, and SSIM analysis for quality assurance
- **🛡️ Robust Error Handling**: Automatic failure recovery and detailed logging
- **📈 Performance Tracking**: Real-time progress and comprehensive statistics

## 📚 Documentation

### 🔗 **Quick Links**

- 📖 [**Complete Documentation**](https://itsfelixh.github.io/powershell-hevc-converter/) - Comprehensive guides and API reference
- 🚀 [**Quick Start Guide**](#-quick-start) - Get up and running in minutes
- 🎯 [**Preset Profiles**](#-preset-profiles) - Optimized settings for different content types
- 💡 [**Examples**](#-examples) - Usage scenarios

### 📋 **Script Overview**

| Script | Description | Use Case |
|--------|-------------|----------|
| 🎬 [**Convert-VideoToHEVC.ps1**](https://itsfelixh.github.io/powershell-hevc-converter/Convert-VideoToHEVC.html) | Main conversion engine | Primary video conversion |
| 📊 [**Analyze-Compression.ps1**](https://itsfelixh.github.io/powershell-hevc-converter/Analyze-Compression.html) | Quality & efficiency analysis | Post-conversion analysis |
| ⚡ [**Optimize-HEVCSettings.ps1**](https://itsfelixh.github.io/powershell-hevc-converter/Optimize-HEVCSettings.html) | Settings optimization | Find optimal encoding parameters |
| ✅ [**Verify-HEVCConversions.ps1**](https://itsfelixh.github.io/powershell-hevc-converter/Verify-HEVCConversions.html) | Integrity validation | Quality assurance & verification |

## 🚀 Quick Start

### 📋 **Prerequisites**

- **PowerShell:** Windows PowerShell or PowerShell Core.
- **FFmpeg and FFprobe:** These command-line tools are essential for the conversion process. They must be installed on your system and accessible via your system's **PATH** environment variable. You can download the latest version from the [official FFmpeg website](https://ffmpeg.org/download.html).

### 📖 **Usage**

1. **Save the Script:** Save the provided PowerShell script as `Convert-VideoToHEVC.ps1` (or any `.ps1` filename) in a convenient location.
2. **Open PowerShell:** Navigate to the directory where you saved the script.
3. **Run the Script:** Execute the script from PowerShell.

```powershell
# Convert all videos in current directory
.\Convert-VideoToHEVC.ps1
```

## 🎯 Preset Profiles

Choose from **10 optimized encoding profiles** tailored for different content types:

| Profile | 🎯 Best For | CRF | Preset | Special Features |
|---------|-------------|-----|--------|------------------|
| 🎨 **Animation** | Cartoons, Anime | 22 | medium | Optimized for flat colors |
| 🎬 **Film** | Movies, TV shows | 23 | slow | Balanced quality/size |
| 🖥️ **ScreenCapture** | Tutorials, Demos | 18 | fast | Sharp text preservation |
| 🏃 **HighMotion** | Sports, Action | 21 | medium | Motion optimization |
| 🌙 **LowLight** | Dark scenes | 20 | slow | Noise reduction |
| 📱 **MobileStream** | Mobile viewing | 26 | fast | Small file sizes |
| 📺 **SocialMedia** | Web sharing | 24 | fast | Platform optimization |
| 🏆 **ArchiveQuality** | Long-term storage | 18 | veryslow | Maximum quality |
| 🎞️ **FilmRestoration** | Old content | 19 | slow | Artifact reduction |
| 🌈 **HDR-8K** | High-end content | 20 | slow | HDR preservation |

## 💡 Examples

### 🎬 **HEVC Conversion**

```powershell
# Convert all videos in a folder
.\Convert-VideoToHEVC.ps1 -inputFolder "D:\Movies" -outputFolder "D:\HEVC_Movies"

# Convert with custom quality settings
.\Convert-VideoToHEVC.ps1 -inputFolder "C:\Videos" -crf 20 -preset slow

# Use optimized preset for specific content
.\Convert-VideoToHEVC.ps1 -Profile Animation -inputFolder "C:\Cartoons"

# Batch processing with progress tracking
.\Convert-VideoToHEVC.ps1 -batchSize 5 -DebugMode -LogToFile
```

### 📊 **Quality Analysis**

```powershell
# Analyze compression results
.\Analyze-Compression.ps1 -SourcePath "D:\Original" -ConvertedPath "D:\HEVC" -OutputFormat HTML
```

### ⚡ **Settings Optimization**

```powershell
# Find optimal settings for your content
.\Optimize-HEVCSettings.ps1 -InputPath "sample.mp4" -QualityTarget 95
```

### ✅ **Verification**

```powershell
# Verify conversion integrity
.\Verify-HEVCConversions.ps1 -SourcePath "D:\Original" -ConvertedPath "D:\HEVC" -VerificationMode Full
```

## 🛠️ Advanced Configuration

### ⚙️ **Custom Parameters**

```powershell
# Advanced conversion with custom settings
.\Convert-VideoToHEVC.ps1 `
    -inputFolder "C:\Source" `
    -outputFolder "C:\Output" `
    -crf 22 `
    -preset medium `
    -batchSize 10 `
    -DebugMode `
    -LogToFile
```

<details>
<summary><strong>ALL PARAMETERS</strong></summary>

| Parameter Name | Type | Default Value | Description |
| :------------- | :--- | :------------ | :---------- |
| `-Profile` | `string` | (Absent) | Predefined encoding profile to use. Options: `Animation`, `Film`, `ScreenCapture`, `HighMotion`, `LowLight`, `MobileStream`, `SocialMedia`, `ArchiveQuality`, `FilmRestoration`, `HDR-8K`. |
| `-inputFolder` | `string` | Current directory | Path to the folder containing video files to be converted. |
| `-outputFolder` | `string` | `.\converted` | Path where converted HEVC video files will be saved. |
| `-batchSize` | `int` | `0` (Disabled) | Number of files to process per batch. The script will pause and prompt for continuation after each batch. Set to `0` to process all files at once. |
| `-crf` | `int` | `23` | Constant Rate Factor (CRF) for `libx265` encoding (0-51). Lower values = higher quality, larger file size. |
| `-preset` | `string` | `medium` | Encoding preset for `libx265`. Controls speed vs. compression efficiency. Options: `ultrafast`, `superfast`, `veryfast`, `faster`, `fast`, `medium`, `slow`, `slower`, `veryslow`, `placebo`. |
| `-DebugMode` | `switch` | (Absent) | Enables verbose debugging output to the console and detailed log entries. |
| `-LogToFile` | `switch` | (Absent) | Writes all console output to a separate log file for later review. |

</details>

### 🎨 **Creating Custom Profile Presets**

Example: Custom preset for gaming content

```json
{
    "name": "Gaming",
    "description": "Optimized for gaming footage with fast motion",
    "crf": 21,
    "preset": "fast",
    "extra_params": [
        "-tune", "fastdecode",
        "-x265-params", "bframes=3:b-adapt=2"
    ]
}
```

## 🔧 Troubleshooting

### ❓ **Common Issues**

<details>
<summary><strong>🚫 FFmpeg not found</strong></summary>

```powershell
# Verify FFmpeg installation
where ffmpeg
ffmpeg -version

# Add to PATH if needed
$env:PATH += ";C:\ffmpeg\bin"
```

</details>

<details>
<summary><strong>⚠️ libx265 not available</strong></summary>

```powershell
# Check for HEVC encoder
ffmpeg -encoders | Select-String "libx265"

# Download FFmpeg with libx265 support
# Visit: https://www.gyan.dev/ffmpeg/builds/
```

</details>

<details>
<summary><strong>🐌 Conversion taking too long</strong></summary>

```powershell
# Use a faster preset
.\Convert-VideoToHEVC.ps1 -preset faster -crf 26

# Process smaller batches
.\Convert-VideoToHEVC.ps1 -batchSize 3
```

</details>

<details>
<summary><strong>📉 Quality issues in output</strong></summary>

```powershell
# Use a lower CRF value (higher quality)
.\Convert-VideoToHEVC.ps1 -crf 18

# Use a slower preset for better quality
.\Convert-VideoToHEVC.ps1 -preset slow

# Use quality-optimized profile
.\Convert-VideoToHEVC.ps1 -Profile ArchiveQuality
```

</details>

### 📞 Support and Issues

If you encounter any issues, have questions, or need assistance, please open an issue on the [GitHub Issues page](https://github.com/itsFelixH/powershell-hevc-converter/issues).

## 🤝 Contributing

Feel free to fork this repository, submit pull requests, or open issues for any improvements, bug fixes, or new features.

### 🎯 **Ways to Contribute**

- 🐛 **Bug Reports**: [Open an issue](https://github.com/itsFelixH/powershell-hevc-converter/issues)
- 💡 **Feature Requests**: [Start a discussion](https://github.com/itsFelixH/powershell-hevc-converter/discussions)
- 🔧 **Code Contributions**: Submit a pull request

### 🚀 **Development Setup**

```powershell
# 1. Fork and clone the repository
git clone https://github.com/YOUR-USERNAME/powershell-hevc-converter.git
cd powershell-hevc-converter

# 2. Create feature branch
git checkout -b feature/your-feature-name

# 3. Make changes and test

# 4. Commit and push
git commit -m "feat: Add new feature"
git push origin feature/your-feature-name

# 5. Open a Pull Request to the main branch.
```
