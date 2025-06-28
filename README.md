# Powershell HEVC Video Converter Script

This PowerShell script automates the conversion of various video formats to HEVC (H.265) using FFmpeg, optimizing for file size while maintaining excellent quality. It's designed for efficient batch processing, handling files recursively within a specified input folder and organizing outputs into a dedicated output directory.

## Features

* **Batch Conversion:** Process multiple video files (`.mkv`, `.mp4`, `.mov`, `.wmv`, `.avi`, `.flv`, `.m4v`) in a specified input directory and its subfolders.
* **HEVC Encoding:** Utilizes the `libx265` encoder for highly efficient H.265 compression, providing a superior balance of quality and file size compared to older codecs like H.264.
* **Customizable Quality:** Easily adjust output quality with the **Constant Rate Factor (CRF)** and choose from a range of encoding **presets** to balance speed and compression efficiency.
* **Smart File Handling:** The script automatically skips already converted files, ensuring you don't waste time re-encoding.
* **Robust Error Handling:** Conversion failures are caught, logged with detailed error messages, and the original problematic files are automatically moved to a `failed` folder for review.
* **Comprehensive Logging:** All significant actions, warnings, and errors are logged to a timestamped file for easy troubleshooting and review.
* **Performance Metrics:** Get a clear summary of total files processed, success and failure rates, total time elapsed, and the amount of disk space saved.
* **Pre-flight Check:** The script validates that both `ffmpeg` and `ffprobe` are installed and available in your system's PATH before starting any conversions.
* **Interactive Batching:** Optionally process files in smaller batches with an interactive prompt after each batch, giving you control over long-running jobs.

## Prerequisites

* **FFmpeg and FFprobe:** These command-line tools are essential for the conversion process. They must be installed on your system and accessible via your system's **PATH** environment variable. You can download the latest version from the [official FFmpeg website](https://ffmpeg.org/download.html).

## Usage

1. **Save the Script:** Save the provided PowerShell script as `Convert-VideoToHEVC.ps1` (or any `.ps1` filename) in a convenient location.
2. **Open PowerShell:** Navigate to the directory where you saved the script.
3. **Run the Script:** Execute the script from PowerShell.

### Basic Usage

To convert all supported video files in the current directory and its subfolders, saving the converted files to a new `converted` folder within the same location:

```powershell
.\\Convert-VideoToHEVC.ps1
```

### Parameters

The script accepts the following parameters to customize its behavior:

| Parameter Name | Type | Default Value | Description |
| :------------- | :--- | :------------ | :---------- |
| `-inputFolder` | `string` | Current directory | Path to the folder containing video files to be converted. |
| `-outputFolder` | `string` | `.\converted` | Path where converted HEVC video files will be saved. |
| `-batchSize` | `int` | `0` (Disabled) |Number of files to process per batch. The script will pause and prompt for continuation after each batch. Set to `0` to process all files at once. |
| `-crf` | `int` | `23` | Constant Rate Factor (CRF) for `libx265` encoding (0-51). Lower values = higher quality, larger file size. |
| `-preset` | `string` | `medium` | Encoding preset for `libx265`. Controls speed vs. compression efficiency. Options: `ultrafast`, `superfast`, `veryfast`, `faster`, `fast`, `medium`, `slow`, `slower`, `veryslow`, `placebo`. |
| `-DebugMode` | `switch` | (Absent) | Enables verbose debugging output to the console and detailed log entries. |
| `-LogToFile` | `switch` | (Absent) | Writes all console output to a separate log file for later review. |

### Examples

**Convert with specific quality and preset:**

```powershell
.\Convert-VideoToHEVC.ps1 -inputFolder "C:\MyVideos" -outputFolder "C:\ConvertedVideos" -crf 20 -preset slow
```

*This command converts videos from `C:\MyVideos` to `C:\ConvertedVideos` using a CRF of 20 (higher quality than default) and the `slow` preset (which provides better compression at the cost of speed).*

**Enable interactive batching and debug logging:**

```powershell
.\Convert-VideoToHEVC.ps1 -batchSize 5 -DebugMode
```

*This will process files in batches of 5, pausing after each batch to ask if you want to continue, and will also print verbose debug messages.*

**Preview the conversion operations (Dry Run):**

```powershell
.\Convert-VideoToHEVC.ps1 -inputFolder ".\Source" -outputFolder ".\Output" -WhatIf
```

*Using the common PowerShell parameter `-WhatIf` will show you exactly what the script would do without actually performing any conversions or file movements.*

## Logging

If the `-LogToFile` switch is used, the script generates a timestamped log file named `yyyy-MM-dd_HH-mm-ss_conversion.log` in the output folder. This log file contains:

* Timestamps for all events.
* Severity levels (Info, Warning, Error, Debug, Success).
* Details of each conversion, including file sizes and compression ratios.
* Full FFmpeg error output for failed conversions.

Review this log file for a complete history of operations and any issues encountered.

## Error Handling

The script implements robust error handling using `Try/Catch` blocks.

* If an FFmpeg conversion fails, the original file is moved to a `failed` subfolder within the input directory, and a detailed error log from FFmpeg is saved alongside it.
* Partial output files from failed conversions are automatically deleted to prevent clutter.

## Advanced FFmpeg Considerations

The script uses a carefully selected set of FFmpeg options to ensure a good balance of quality, compression, and compatibility:

* **Pixel Format (`-pix_fmt yuv420p10le`):** This setting encodes the video in 10-bit color depth, which often results in smaller files than 8-bit for a given quality level, while avoiding banding artifacts.
* **Video Tag (`-tag:v hvc1`):** This tag ensures broader compatibility, particularly with Apple devices and modern media players.
* **Discard Chapters (`-map_chapters -1`):** This helps reduce metadata overhead in the output file, keeping it clean and lightweight.
* **Audio and Subtitle Passthrough (`-c:a copy -c:s copy`):** Audio and subtitle tracks are copied directly from the source file without re-encoding, saving time and preserving original quality.

For more advanced FFmpeg options or to explore hardware acceleration (e.g., NVENC, QSV), refer to the [FFmpeg documentation](https://ffmpeg.org/documentation.html) and specific encoder guides (e.g., [H.265 Encoding Guide](https://trac.ffmpeg.org/wiki/Encode/H.265)).

## Contributing

Feel free to fork this repository, submit pull requests, or open issues for any improvements or bug fixes. Your contributions are welcome!
