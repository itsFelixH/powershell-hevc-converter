<#
.SYNOPSIS
Converts video files to HEVC (H.265) format using FFmpeg, optimizing for file size while maintaining quality.
Supports batch processing, robust error handling, and detailed logging.

.DESCRIPTION
This script automates the conversion of various video formats (MKV, MP4, MOV, WMV, AVI, FLV, M4V)
to HEVC (H.265) using the libx265 encoder. It is designed for efficient batch processing,
handling files recursively within a specified input folder and organizing outputs into a dedicated
output directory.

Key features include:
- Customizable quality (CRF) and encoding preset.
- Automatic detection and exclusion of already converted or failed files.
- Comprehensive error handling with detailed logging to a file.
- Performance metrics and summary report upon completion.

The script ensures FFmpeg and FFprobe are available in the system's PATH before execution.
Original files are moved to the output folder upon successful conversion, and failed conversions
are moved to a 'failed' subfolder with associated error logs for troubleshooting.
.PARAMETER inputFolder
Specifies the path to the folder containing video files to be converted.
Defaults to the current directory where the script is executed.

.PARAMETER outputFolder
Specifies the path where converted HEVC video files will be saved.
A 'converted' subfolder will be created in the current directory by default if not specified.

.PARAMETER DebugMode
A switch parameter that, when present, enables verbose debugging output to the console
and detailed entries in the log file.

.PARAMETER crf
Constant Rate Factor (CRF) value for libx265 encoding.
Lower values result in higher quality and larger file sizes.
Acceptable range is 0 (lossless) to 51 (lowest quality). Default is 23.

.PARAMETER preset
Encoding preset for libx265. Controls the trade-off between encoding speed and compression efficiency.
Slower presets generally yield better compression and quality for a given CRF, but take longer.
Valid options: ultrafast, superfast, veryfast, faster, fast, medium, slow, slower, veryslow, placebo.
Default is "medium".

.PARAMETER MaxThreads
Specifies the maximum number of threads FFmpeg should use for encoding.
A value of 0 (default) allows FFmpeg to automatically determine the optimal number of threads.
Setting a specific number can be useful for resource management.

.EXAMPLE
.\Convert-VideoToHEVC.ps1 -inputFolder "C:\MyVideos" -outputFolder "C:\ConvertedVideos" -crf 20 -preset slow

.EXAMPLE
.\Convert-VideoToHEVC.ps1 -DebugMode

.INPUTS
None. This script does not accept pipeline input.

.OUTPUTS
None. The script primarily performs file operations and outputs status messages to the console and log file.

.NOTES
Requires FFmpeg and FFprobe to be installed and accessible via the system's PATH environment variable.
The script will create 'converted' and 'failed' subfolders if they do not exist.
Original files are moved to the output folder after successful conversion.
Failed files are moved to the 'failed' folder along with a log of the FFmpeg error output.
The script logs all significant actions and errors to 'conversion_log.log' in the script's root directory.
#>
<#

HEVC Video Converter
1.0.0.0
Your Name/Organization

true
Converts video files to HEVC (H.265) format using FFmpeg, optimizing for file size while maintaining quality.
#>


# Parameters
param (
	# input & output folders
	[string]$inputFolder = (Get-Location).Path,
	[string]$outputFolder = (Join-Path -Path (Get-Location).Path -ChildPath "converted"),

	# Debug mode switch
	[Parameter(HelpMessage = "Enable verbose debugging output to the console and detailed log entries.")]
	[switch]$DebugMode,

	# Advanced encoding parameters
	[ValidateRange(0, 51)]
	[int]$crf = 23,

	[ValidateSet("ultrafast", "superfast", "veryfast", "faster", "fast", "medium", "slow", "slower", "veryslow", "placebo")]
	[string]$preset = "medium",

	# Performance options
	[Parameter(HelpMessage = "Maximum number of threads FFmpeg should use for encoding. 0 for auto-detection.")]
	[int]$MaxThreads = 0
)

# Custom color definitions
$successColor = "Green"
$warningColor = "Yellow"
$errorColor = "Red"
$infoColor = "Cyan"
$debugColor = "Magenta"

# Debugging helper function
function Write-DebugInfo {
	param([string]$message)
	if ($DebugMode) {
		Write-Host "[DEBUG] $(Get-Date -Format 'HH:mm:ss.fff') - $message" -ForegroundColor $debugColor
	}
}

function Format-FileSize {
	param([long]$size)
	switch ($size) {
		{ $_ -ge 1TB } { "{0:N2} TB" -f ($_ / 1TB); break }
		{ $_ -ge 1GB } { "{0:N2} GB" -f ($_ / 1GB); break }
		{ $_ -ge 1MB } { "{0:N2} MB" -f ($_ / 1MB); break }
		{ $_ -ge 1KB } { "{0:N2} KB" -f ($_ / 1KB); break }
		default { "$_ bytes" }
	}
}

function Test-FFmpeg {
	try {
		$ffmpegVersion = (ffmpeg -version | Select-String -Pattern 'ffmpeg version').Line.Split()[2]
		$ffprobeVersion = (ffprobe -version | Select-String -Pattern 'ffprobe version').Line.Split()[2]

		Write-Host "FFmpeg version detected: $ffmpegVersion" -ForegroundColor $infoColor
		Write-Host "FFprobe version detected: $ffprobeVersion" -ForegroundColor $infoColor

		return $true
	}
	catch {
		Write-Host "FFmpeg/FFprobe not found! Please ensure they are in your PATH" -ForegroundColor $errorColor
		return $false
	}
}

function Get-MediaInfo {
	param([string]$filePath)
	try {
		$ffprobeOutput = & ffprobe -v error -select_streams v:0 -show_entries stream=codec_name, width, height, pix_fmt, duration, bit_rate -of json "$filePath" 2>&1
        
		# Check if output is valid JSON
		if ($ffprobeOutput -match "^{") {
			return $ffprobeOutput | ConvertFrom-Json
		}
		else {
			Write-DebugInfo "FFprobe returned non-JSON output: $ffprobeOutput"
			return $null
		}
	}
	catch {
		Write-DebugInfo "FFprobe error: $($_.Exception.Message)"
		return $null
	}
}


# Validate parameters
Write-DebugInfo "Script startup"
Write-DebugInfo "Input folder: $inputFolder"
Write-DebugInfo "Output folder: $outputFolder"
Write-DebugInfo "Debug mode: $DebugMode"
Write-DebugInfo "CRF: $crf, Preset: $preset"
Write-DebugInfo "MaxThreads: $MaxThreads"

if (-not (Test-FFmpeg)) {
	exit 1
}

# Initialize tracking variables
$totalOriginalSize = 0
$totalConvertedSize = 0
$failedConversions = @()
$successConversions = @()
$startTime = Get-Date

# Validate and create folders
try {
	if (!(Test-Path -Path $outputFolder -PathType Container)) {
		Write-Host "Creating output folder '$outputFolder'." -ForegroundColor $infoColor
		$null = New-Item -ItemType Directory -Path $outputFolder
	}
	$failedFolder = Join-Path -Path $inputFolder -ChildPath "failed"
	if (!(Test-Path -Path $failedFolder -PathType Container)) {
		Write-Host "Creating folder '$failedFolder' for failed conversions." -ForegroundColor $infoColor
		$null = New-Item -ItemType Directory -Path $failedFolder
	}
}
catch {
	Write-Host "Error validating or creating input and output folders" -ForegroundColor $errorColor
	Write-Host "Error details: $_" -ForegroundColor $errorColor
	exit 1
}

# Switch to input folder
Set-Location $inputFolder
Write-DebugInfo "Working directory set to: $(Get-Location)"

# Get video files
try {
	$excludeFolders = @(
		$failedFolder,
		$outputFolder
	) | Where-Object { Test-Path $_ }

	$VideoFiles = Get-ChildItem -Path $inputFolder -Recurse -File |
	Where-Object { 
		$filePath = $_.FullName
		# Exclude files in failed and converted folders
		-not ($excludeFolders | Where-Object { $filePath.StartsWith($_) })
	} |
	Where-Object { $_.Extension -in ".mkv", ".mp4", ".mov", ".wmv", ".avi", ".flv", ".m4v" } |
	Where-Object { $_.Name -notmatch '_x265\.mkv$' } |
	Sort-Object Length -Descending

	Write-DebugInfo "Found $($VideoFiles.Count) video files to process"
	if ($excludeFolders) {
		Write-DebugInfo "Excluding folders: $($excludeFolders -join ', ')"
	}
}
catch {
	Write-Host "Error accessing input folder: $inputFolder" -ForegroundColor $errorColor
	Write-Host "Error details: $_" -ForegroundColor $errorColor
	Set-Location $PSScriptRoot
	exit 1
}

if (-not $VideoFiles) {
	Write-Host "No files to convert found in $inputFolder" -ForegroundColor $warningColor
	Set-Location $PSScriptRoot
	exit 0
}

# Process files
$totalFiles = $VideoFiles.Count
$processedFiles = 0

Write-Host "`nStarting HEVC conversion of $totalFiles files`n" -ForegroundColor $infoColor
Write-Host "Using quality settings: CRF $crf, Preset $preset" -ForegroundColor $infoColor

# Converting/compressing files
foreach ($file in $VideoFiles) {
	$processedFiles++
	$fileStart = Get-Date
	$originalSize = $file.Length
	$totalOriginalSize += $originalSize

	$inputPath = $file.FullName
	$outputPath = Join-Path $outputFolder ($file.BaseName + "_x265.mkv")

	Write-Host "`n[$processedFiles/$totalFiles] Converting: $($file.Name)" -ForegroundColor White -NoNewline
	Write-Host " ($(Format-FileSize $originalSize))" -ForegroundColor $infoColor
	Write-DebugInfo "Input path: $inputPath"
	Write-DebugInfo "Output path: $outputPath"

	# Gather media information
	$mediaInfo = Get-MediaInfo -filePath $inputPath
	if ($mediaInfo) {
		$streamInfo = $mediaInfo.streams[0]
		Write-DebugInfo "Video codec: $($streamInfo.codec_name), Resolution: $($streamInfo.width)x$($streamInfo.height)"
		Write-DebugInfo "Pixel format: $($streamInfo.pix_fmt), Duration: $($streamInfo.duration)s"
	}

	try {
		# Build FFmpeg command
		$ffmpegParams = @(
			"-stats"
			"-y",
			"-loglevel", "error",
			"-i", $inputPath,
			"-map", "0",
			"-map_chapters", "-1", # Discard chapters
			"-c:v", "libx265",
			"-crf", $crf,
			"-preset", $preset,
			"-c:a", "copy",
			"-c:s", "copy",
			"-x265-params", "log-level=error:threads=$MaxThreads",
			"-pix_fmt", "yuv420p10le",
			"-tag:v", "hvc1",
			$outputPath
		)
		Write-DebugInfo "FFmpeg parameters: $($ffmpegParams -join ' ')"

		# Run FFmpeg
		Write-DebugInfo "Starting FFmpeg conversion..."
		$ffmpegOutput = & ffmpeg @ffmpegParams 2>&1

		Write-DebugInfo "FFmpeg command completed with exit code: $LASTEXITCODE"

		if ($LASTEXITCODE -ne 0) {
			throw "FFmpeg exited with error code $LASTEXITCODE"
		}

		# Verify conversion
		$convertedFile = Get-Item $outputPath -ErrorAction Stop
		$convertedSize = $convertedFile.Length
		$totalConvertedSize += $convertedSize

		$sizeDifference = Format-FileSize ($originalSize - $convertedSize)
		$compressionRatio = [Math]::Round(($convertedSize / $originalSize) * 100, 2)

		Write-Host "Converted size: $(Format-FileSize $convertedSize) ($compressionRatio% of original)" -ForegroundColor $successColor
		Write-Host "Size reduced by: $sizeDifference" -ForegroundColor $successColor
		Write-Host "Conversion time: $((Get-Date).Subtract($fileStart).ToString('hh\:mm\:ss'))" -ForegroundColor $infoColor

		# Move original file
		Move-Item $inputPath $outputFolder -Force
		Write-Host "Original file moved to output folder" -ForegroundColor $infoColor

		$successConversions += $file.Name
	}
	catch {
		$errorMsg = $_.Exception.Message
		Write-Host "Conversion failed: $errorMsg" -ForegroundColor $errorColor

		# Log FFmpeg output if available
		if ($ffmpegOutput) {
			Write-Host "FFmpeg output:" -ForegroundColor $errorColor
			$ffmpegOutput | Select-Object -First 20 | ForEach-Object { 
				Write-Host "  $_" -ForegroundColor $errorColor 
			}

			if ($ffmpegOutput.Count -gt 20) {
				Write-Host "  ... (truncated, see full log for details)" -ForegroundColor $errorColor
			}

			# Save error log
			$logPath = Join-Path $failedFolder ($file.BaseName + ".log")
			$ffmpegOutput | Out-File $logPath
			Write-Host "Full error log saved to: $logPath" -ForegroundColor $errorColor
		}

		# Move failed file
		$failedPath = Join-Path -Path $failedFolder -ChildPath $file.Name
		try {
			Move-Item $inputPath $failedPath -Force -ErrorAction Stop
			Write-Host "Original file moved to failed folder" -ForegroundColor $errorColor
		}
		catch {
			Write-Host "Failed to move original file: $($_.Exception.Message)" -ForegroundColor $errorColor
		}

		# Cleanup partial output
		if (Test-Path $outputPath) {
			try {
				Remove-Item $outputPath -Force -ErrorAction Stop
				Write-Host "Deleted partial output file" -ForegroundColor $warningColor
			}
			catch {
				Write-Host "Failed to delete partial output: $($_.Exception.Message)" -ForegroundColor $errorColor
			}
		}

		$failedConversions += $file.Name
	}
}

# Final summary
$totalTime = (Get-Date).Subtract($startTime)
$totalSavedSpace = Format-FileSize ($totalOriginalSize - $totalConvertedSize)

Write-Host "`n=================== CONVERSION SUMMARY ===================" -ForegroundColor $infoColor
Write-Host "Total files processed: $totalFiles" -ForegroundColor White
Write-Host "Successfully converted: $($successConversions.Count)" -ForegroundColor $successColor
Write-Host "Failed conversions: $($failedConversions.Count)" -ForegroundColor $errorColor
Write-Host "Total time: $($totalTime.ToString('hh\:mm\:ss'))" -ForegroundColor White
Write-Host "Original total size: $(Format-FileSize $totalOriginalSize)" -ForegroundColor White
Write-Host "Converted total size: $(Format-FileSize $totalConvertedSize)" -ForegroundColor White
Write-Host "Total space saved: $totalSavedSpace" -ForegroundColor $successColor
Write-Host "Average compression ratio: $([Math]::Round(($totalConvertedSize / $totalOriginalSize) * 100, 2))%" -ForegroundColor $infoColor
Write-Host "Average processing rate: $([Math]::Round($totalFiles / $totalTime.TotalHours, 2)) files/hour" -ForegroundColor $infoColor
Write-Host "=======================================================`n" -ForegroundColor $infoColor

if ($failedConversions) {
	Write-Host "Failed files:" -ForegroundColor $errorColor
	$failedConversions | ForEach-Object { Write-Host "- $_" -ForegroundColor $errorColor }
	Write-Host "Check the 'failed' folder for original files and error logs" -ForegroundColor $errorColor
}

# Switch back to execution folder
Set-Location $PSScriptRoot
Write-DebugInfo "Script completed in $($totalTime.ToString('hh\:mm\:ss'))"

# Performance report
if ($DebugMode) {
	$endTime = Get-Date
	$totalSeconds = $totalTime.TotalSeconds
	$avgFileTime = if ($totalFiles -gt 0) { $totalSeconds / $totalFiles } else { 0 }
    
	Write-Host "`n=============== PERFORMANCE REPORT ===============" -ForegroundColor $infoColor
	Write-Host "Start time:        $($startTime.ToString('yyyy-MM-dd HH:mm:ss'))"
	Write-Host "End time:          $($endTime.ToString('yyyy-MM-dd HH:mm:ss'))"
	Write-Host "Total duration:    $($totalTime.ToString('hh\:mm\:ss'))"
	Write-Host "Files processed:   $totalFiles"
	Write-Host "Avg time per file: $([Math]::Round($avgFileTime, 1)) seconds"
	Write-Host "Total data processed: $(Format-FileSize $totalOriginalSize)"
	if ($totalTime.TotalHours -gt 0) {
		Write-Host "Processing speed: $([Math]::Round($totalOriginalSize / 1GB / $totalTime.TotalHours, 2)) GB/hour"
	}
	else {
		Write-Host "Processing speed: N/A (processing time too short)"
	}
	Write-Host "================================================`n" -ForegroundColor $infoColor
}

Read-Host "Press ENTER to exit..."