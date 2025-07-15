# Convert-VideoToHEVC

## Synopsis



Converts video files to HEVC (H.265) format using FFmpeg with advanced options, batch processing, and robust error handling.

## Description



This script automates the conversion of various video formats (MKV, MP4, MOV, WMV, AVI, FLV, M4V)
to HEVC (H.265) using the libx265 encoder. It supports preset profiles for different content types and robust error handling.

Key features include:
- Preset profiles for different content types (Animation, Film, ScreenCapture, etc.)
- Customizable quality (CRF) and encoding preset.
- Optional interactive batch processing to convert files in chunks.
- Comprehensive error handling with detailed logging to a file and console.
- Dry-run mode using the -WhatIf common parameter to preview operations without making changes.
- Performance metrics and a summary report upon completion.
- Automatic detection and exclusion of already converted files.
- Ensures FFmpeg and FFprobe are available in the system's PATH before execution.
- Original files are moved to the output folder upon successful conversion, and failed conversions are moved to a 'failed' subfolder for troubleshooting.

### Parameter: $paramName



Specifies a predefined encoding profile to use for conversion

### Parameter: $paramName



Specifies the path to the folder containing video files to be converted.
Defaults to the current directory where the script is executed.

### Parameter: $paramName



Specifies the path where converted HEVC video files will be saved.
A 'converted' subfolder will be created in the current directory by default if not specified.

### Parameter: $paramName



Specifies the number of files to process in each batch. The script will pause and prompt for
continuation after each batch. If not specified, all files will be processed at once.

### Parameter: $paramName



Constant Rate Factor (CRF) value for libx265 encoding.
Lower values result in higher quality and larger file sizes.
Acceptable range is 0 (lossless) to 51 (lowest quality). Default is 28.

### Parameter: $paramName



Encoding preset for libx265. Controls the trade-off between encoding speed and compression efficiency.
Slower presets generally yield better compression and quality for a given CRF, but take longer.
Valid options: ultrafast, superfast, veryfast, faster, fast, medium, slow, slower, veryslow, placebo.
Default is "medium".

### Parameter: $paramName



A switch parameter that, when present, enables verbose debugging output to the console
and detailed entries in the log file.

### Parameter: $paramName



A switch parameter that, when present, writes all console output to a separate log file.

### Example

`powershell

.\Convert-VideoToHEVC.ps1 -Profile Animation

`

.\Convert-VideoToHEVC.ps1 -Profile Animation

### Example

`powershell

.\Convert-VideoToHEVC.ps1 -Profile Animation

`

.\Convert-VideoToHEVC.ps1 -inputFolder "C:\MyVideos" -outputFolder "C:\ConvertedVideos" -crf 20 -preset slow

### Example

`powershell

.\Convert-VideoToHEVC.ps1 -Profile Animation

`

.\Convert-VideoToHEVC.ps1 -batchSize 5 -crf 25 -preset fast

### Example

`powershell

.\Convert-VideoToHEVC.ps1 -Profile Animation

`

.\Convert-VideoToHEVC.ps1 -DebugMode -LogToFile

### Example

`powershell

.\Convert-VideoToHEVC.ps1 -Profile Animation

`

.\Convert-VideoToHEVC.ps1 -inputFolder ".\Source" -outputFolder ".\Output" -WhatIf

## Inputs



None. This script does not accept pipeline input.

## Outputs



None. The script primarily performs file operations and outputs status messages to the console and log file.

## Notes



Requires FFmpeg and FFprobe to be installed and accessible via the system's PATH environment variable.
The script creates 'converted' and 'failed' subfolders if they do not exist.
Original files are moved to the output folder after successful conversion.
Failed files are moved to the 'failed' folder along with a log of the FFmpeg error output.
The script logs significant actions and errors to 'yyyy-MM-dd_HH-mm-ss_conversion.log' in the script's root directory if -LogToFile is specified.

