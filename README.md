# HEVC Video Converter

This PowerShell script automates the conversion of various video formats to HEVC (H.265) using FFmpeg, optimizing for file size while maintaining quality. It's designed for efficient batch processing, handling files recursively within a specified input folder and organizing outputs into a dedicated output directory.

## Features

* **Batch Conversion:** Processes multiple video files (`.mkv`, `.mp4`, `.mov`, `.wmv`, `.avi`, `.flv`, `.m4v`) in a specified input directory and its subfolders.
* **HEVC Encoding:** Utilizes the `libx265` encoder for efficient H.265 compression.
* **Customizable Quality:** Adjust output quality using the Constant Rate Factor (CRF) and encoding preset.
* **Smart File Handling:** Automatically skips already converted files and excludes files from `output` and `failed` directories.
* **Robust Error Handling:** Catches conversion failures, logs detailed error messages, and moves problematic original files to a `failed` folder for review.
* **Comprehensive Logging:** All significant actions, warnings, and errors are logged to a `conversion_log.log` file.
* **Performance Metrics:** Provides a summary of total files processed, conversion success/failure rates, total time, and space saved.

## Prerequisites

* **FFmpeg and FFprobe:** These tools must be installed on your system and accessible via your system's PATH environment variable. You can download them from the [official FFmpeg website](https://ffmpeg.org/download.html).

## Usage

1. **Save the Script:** Save the provided PowerShell script as `Convert-VideoToHEVC.ps1` (or any `.ps1` filename).
2. **Open PowerShell:** Navigate to the directory where you saved the script using `cd <path_to_script>`.
3. **Run the Script:** Execute the script from PowerShell.

### Basic Usage

To convert all supported video files in the current directory and its subfolders, saving the converted files to a new `converted` folder

```powershell
.\\Convert-VideoToHEVC.ps1
```

### Parameters

The script accepts the following parameters to customize its behavior:

| Parameter Name | Type | Default Value | Description |
| :------------- | :--- | :------------ | :---------- |
| `-inputFolder` | `string` | Current directory | Path to the folder containing video files to be converted. |
| `-outputFolder` | `string` | `.\converted` | Path where converted HEVC video files will be saved. |
| `-DebugMode` | `switch` | (Absent) | Enables verbose debugging output to the console and detailed log entries. |
| `-crf` | `int` | `23` | Constant Rate Factor (CRF) for `libx265` encoding (0-51). Lower values = higher quality, larger file size. |
| `-preset` | `string` | `medium` | Encoding preset for `libx265`. Controls speed vs. compression efficiency. Options: `ultrafast`, `superfast`, `veryfast`, `faster`, `fast`, `medium`, `slow`, `slower`, `veryslow`, `placebo`. |
| `-MaxThreads` | `int` | `0` (auto) | Maximum number of threads FFmpeg should use for encoding. `0` lets FFmpeg decide. |

### Examples

**Convert with specific quality and preset:**

```powershell
.\Convert-VideoToHEVC.ps1 -inputFolder "C:\MyVideos" -outputFolder "C:\ConvertedVideos" -crf 20 -preset slow
````

*This command will convert videos from `C:\MyVideos` to `C:\ConvertedVideos` using a CRF of 20 (higher quality than default) and the `slow` preset (better compression, longer time).*

**Enable Debug Mode:**

```powershell
.\Convert-VideoToHEVC.ps1 -DebugMode
```

*This will show detailed debugging messages in the console and log file.*

## Logging

The script generates a log file named `conversion_log.log` in the same directory as the script. This log file contains:

* Timestamps for all events.
* Severity levels (Info, Warning, Error, Debug, Success).
* Details of each conversion, including file sizes and compression ratios.
* Full FFmpeg error output for failed conversions, aiding in troubleshooting.

Review this log file for a complete history of operations and any issues encountered.

## Error Handling

The script implements robust error handling using `Try/Catch` blocks.

* If an FFmpeg conversion fails, the original file is moved to a `failed` subfolder within the input directory, and a detailed error log from FFmpeg is saved alongside it.
* Partial output files from failed conversions are automatically deleted to prevent clutter.
* All errors are logged to `conversion_log.log` with full exception details.

## Advanced FFmpeg Considerations

The script uses `libx265` as the HEVC encoder, which generally offers superior quality and smaller file sizes compared to hardware encoders, though at a slower speed. [1, 2]

* **Pixel Format (`-pix_fmt yuv420p10le`):** This setting is chosen for `libx265` as 10-bit HEVC often results in smaller files than 8-bit, and 4:2:0 chroma subsampling is a common and efficient choice for general video. [1]
* **Video Tag (`-tag:v hvc1`):** This tag ensures broader compatibility, especially with Apple devices and various media players.
* **Discard Chapters (`-map_chapters -1`):** This helps reduce metadata overhead in the output file.

For more advanced FFmpeg options or to explore hardware acceleration (e.g., NVENC, QSV), refer to the [FFmpeg documentation](https://ffmpeg.org/documentation.html) and specific encoder guides (e.g., [H.265 Encoding Guide](https://trac.ffmpeg.org/wiki/Encode/H.265)).

## Contributing

Feel free to fork this repository, submit pull requests, or open issues for any improvements or bug fixes.
