<#
.SYNOPSIS
Converts video files to HEVC (H.265) format using FFmpeg with advanced options, batch processing, and robust error handling.

.DESCRIPTION
This script automates the conversion of various video formats (MKV, MP4, MOV, WMV, AVI, FLV, M4V)
to HEVC (H.265) using the libx265 encoder. It combines the advanced features, and robust error handling of one script with the
interactive batch processing capability of another.

Key features include:
- Customizable quality (CRF) and encoding preset.
- Optional interactive batch processing to convert files in chunks.
- Comprehensive error handling with detailed logging to a file and console.
- Dry-run mode using the -WhatIf common parameter to preview operations without making changes.
- Performance metrics and a summary report upon completion.
- Automatic detection and exclusion of already converted files.
- Ensures FFmpeg and FFprobe are available in the system's PATH before execution.
- Original files are moved to the output folder upon successful conversion, and failed conversions are moved to a 'failed' subfolder for troubleshooting.

.PARAMETER inputFolder
Specifies the path to the folder containing video files to be converted.
Defaults to the current directory where the script is executed.

.PARAMETER outputFolder
Specifies the path where converted HEVC video files will be saved.
A 'converted' subfolder will be created in the current directory by default if not specified.

.PARAMETER batchSize
Specifies the number of files to process in each batch. The script will pause and prompt for
continuation after each batch. If not specified, all files will be processed at once.

.PARAMETER crf
Constant Rate Factor (CRF) value for libx265 encoding.
Lower values result in higher quality and larger file sizes.
Acceptable range is 0 (lossless) to 51 (lowest quality). Default is 23.

.PARAMETER preset
Encoding preset for libx265. Controls the trade-off between encoding speed and compression efficiency.
Slower presets generally yield better compression and quality for a given CRF, but take longer.
Valid options: ultrafast, superfast, veryfast, faster, fast, medium, slow, slower, veryslow, placebo.
Default is "medium".

.PARAMETER DebugMode
A switch parameter that, when present, enables verbose debugging output to the console
and detailed entries in the log file.

.PARAMETER LogToFile
A switch parameter that, when present, writes all console output to a separate log file.

.EXAMPLE
.\Convert-VideoToHEVC.ps1 -inputFolder "C:\MyVideos" -outputFolder "C:\ConvertedVideos" -crf 20 -preset slow

.EXAMPLE
.\Convert-VideoToHEVC.ps1 -batchSize 5 -crf 25 -preset fast

.EXAMPLE
.\Convert-VideoToHEVC.ps1 -DebugMode -LogToFile

.EXAMPLE
.\Convert-VideoToHEVC.ps1 -inputFolder ".\Source" -outputFolder ".\Output" -WhatIf

.INPUTS
None. This script does not accept pipeline input.

.OUTPUTS
None. The script primarily performs file operations and outputs status messages to the console and log file.

.NOTES
Requires FFmpeg and FFprobe to be installed and accessible via the system's PATH environment variable.
The script creates 'converted' and 'failed' subfolders if they do not exist.
Original files are moved to the output folder after successful conversion.
Failed files are moved to the 'failed' folder along with a log of the FFmpeg error output.
The script logs significant actions and errors to 'yyyy-MM-dd_HH-mm-ss_conversion.log' in the script's root directory if -LogToFile is specified.
#>

# Parameters
[CmdletBinding(SupportsShouldProcess = $true)]
param (
    # input & output folders
    [string]$inputFolder = (Get-Location).Path,
    [string]$outputFolder = (Join-Path -Path (Get-Location).Path -ChildPath "converted"),

    # Advanced encoding parameters
    [Parameter(HelpMessage = "Number of files to process in each batch. Omit for no batching.")]
    [int]$batchSize = 0,

    [ValidateRange(0, 51)]
    [int]$crf = 23,

    [ValidateSet("ultrafast", "superfast", "veryfast", "faster", "fast", "medium", "slow", "slower", "veryslow", "placebo")]
    [string]$preset = "medium",

    # Debug mode switch
    [Parameter(HelpMessage = "Enable verbose debugging output.")]
    [switch]$DebugMode,

    # Logging switch
    [Parameter(HelpMessage = "Write all console output to a log file.")]
    [switch]$LogToFile
)

# Custom color definitions
$successColor = "Green"
$warningColor = "Yellow"
$errorColor = "Red"
$infoColor = "Cyan"
$debugColor = "Magenta"

# Log file path
$logFileTimestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$logFilePath = Join-Path -Path $outputFolder -ChildPath "${logFileTimestamp}_conversion.log"

# Define a function for logging to console and file
function Write-Log {
    param (
        [Parameter(Mandatory = $true)]
        [string]$message,
        [string]$foregroundColor = "White"
    )
    # Output to console
    Write-Host "$message" -ForegroundColor $foregroundColor

    # Output to log file if enabled
    if ($LogToFile) {
        $timestampedMessage = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $message"
        Add-Content -Path $logFilePath -Value $timestampedMessage
    }
}

# Debugging helper function
function Write-DebugInfo {
    param([string]$message)
    if ($DebugMode) {
        Write-Log "[DEBUG] $(Get-Date -Format 'HH:mm:ss.fff') - $message" -foregroundColor $debugColor
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
        $ffmpegFullOutput = ffmpeg -version 2>&1 | Out-String
        $ffmpegVersion = ($ffmpegFullOutput | Select-String -Pattern 'ffmpeg version').Line.Split()[2]

        $ffprobeFullOutput = ffprobe -version 2>&1 | Out-String
        $ffprobeVersion = ($ffprobeFullOutput | Select-String -Pattern 'ffprobe version').Line.Split()[2]

        # Check if libx265 encoder is available
        $x265EncoderInfo = ffmpeg -encoders | Select-String -Pattern 'libx265'
        if (-not $x265EncoderInfo) {
            Write-Log "FFmpeg found, but 'libx265' encoder is not available. Please use a build with HEVC support." -foregroundColor $errorColor
            return $false
        }

        Write-Log "FFmpeg version: $ffmpegVersion" -foregroundColor $infoColor
        Write-Log "FFprobe version: $ffprobeVersion" -foregroundColor $infoColor

        return $true
    }
    catch {
        Write-Log "FFmpeg/FFprobe not found! Please ensure they are in your system's PATH." -foregroundColor $errorColor
        return $false
    }
}

function Get-MediaInfo {
    param([string]$filePath)

    Write-DebugInfo "Attempting to get media info for: $filePath"

    if (-not (Test-Path $filePath -PathType Leaf)) {
        Write-DebugInfo "File not found: $filePath"
        return $null
    }

    try {
        $ffprobeParams = @(
            "-v", "error",
            "-select_streams", "v:0",
            "-show_entries", "stream=codec_name,width,height,pix_fmt,duration,bit_rate",
            "-of", "json",
            $filePath
        )

        Write-DebugInfo "Executing: ffprobe $($ffprobeParams -join ' ')"
        $ffprobeOutput = & ffprobe @ffprobeParams 2>&1

        if ($LASTEXITCODE -ne 0) {
            Write-DebugInfo "FFprobe exited with code $LASTEXITCODE. Output: `n$ffprobeOutput"
            return $null
        }

        $ffprobeOutputString = ($ffprobeOutput | Out-String).Trim()
        if ($ffprobeOutputString.StartsWith("{") -and $ffprobeOutputString.EndsWith("}")) {
            Write-DebugInfo "FFprobe returned valid JSON. Parsing..."
            $mediaInfo = $ffprobeOutputString | ConvertFrom-Json -ErrorAction Stop
        }
        else {
            Write-DebugInfo "FFprobe did not return valid JSON for '$filePath'."
            Write-DebugInfo "FFprobe raw output: `n$ffprobeOutputString"
            return $null
        }

        if ($null -eq $mediaInfo -or $null -eq $mediaInfo.streams -or $mediaInfo.streams.Count -eq 0) {
            Write-DebugInfo "Could not parse video stream info from ffprobe output for '$filePath'."
            return $null
        }

        Write-DebugInfo "Successfully retrieved info for '$filePath'."
        return $mediaInfo.streams[0]
    }
    catch {
        Write-DebugInfo "FFprobe error for '$filePath': $($_.Exception.Message)"
        return $null
    }
}


# Validate parameters
Write-DebugInfo "Script startup"
Write-DebugInfo "Input folder: $inputFolder"
Write-DebugInfo "Output folder: $outputFolder"
if ($batchSize -gt 0) {
    Write-DebugInfo "Batch size: $batchSize"
}
Write-DebugInfo "Debug mode: $DebugMode"
Write-DebugInfo "Log to file: $LogToFile"
Write-DebugInfo "CRF: $crf, Preset: $preset"


# Initialize log file
if ($LogToFile) {
    Write-Host "Creating log file: $logFilePath" -ForegroundColor Gray
    Add-Content -Path $logFilePath -Value "Conversion log started at $(Get-Date)`n"
}

# Validate FFmpeg
if (-not (Test-FFmpeg)) {
    exit 1
}

# Validate and create folders
try {
    if (-not (Test-Path -Path $outputFolder -PathType Container)) {
        Write-Log "Creating output folder '$outputFolder'." -foregroundColor $infoColor
        $null = New-Item -ItemType Directory -Path $outputFolder -Force
    }
    $failedFolder = Join-Path -Path $inputFolder -ChildPath "failed"
    if (-not (Test-Path -Path $failedFolder -PathType Container)) {
        Write-Log "Creating folder '$failedFolder' for failed conversions." -foregroundColor $infoColor
        $null = New-Item -ItemType Directory -Path $failedFolder -Force
    }
}
catch {
    Write-Log "Error validating or creating input/output folders. Details: $_" -foregroundColor $errorColor
    exit 1
}

# Switch to input folder
Set-Location $inputFolder
Write-DebugInfo "Working directory set to: $(Get-Location)"

# Get video files to process
try {
    $excludeFolders = @(
        $failedFolder,
        $outputFolder
    ) | Where-Object { Test-Path $_ }

    $videoFiles = Get-ChildItem -Path $inputFolder -Recurse -File |
    Where-Object {
        $filePath = $_.FullName
        # Exclude files in failed and converted folders
        -not ($excludeFolders | Where-Object { $filePath.StartsWith($_) })
    } |
    Where-Object { $_.Extension -match '\.(mkv|mp4|mov|wmv|avi|flv|m4v)$' } |
    Where-Object { $_.Name -notmatch '_x265\.mkv$' } | # Exclude already converted files
    Sort-Object Length -Descending

    Write-DebugInfo "Found $($videoFiles.Count) video files to process."
    if ($excludeFolders) {
        Write-DebugInfo "Excluding files from folders: $($excludeFolders -join ', ')"
    }
}
catch {
    Write-Log "Error accessing input folder: $inputFolder. Details: $_" -foregroundColor $errorColor
    Set-Location $PSScriptRoot
    exit 1
}

if (-not $videoFiles) {
    Write-Log "No unconverted video files found in $inputFolder." -foregroundColor $warningColor
    Set-Location $PSScriptRoot
    exit 0
}

# Initialize tracking variables
$totalFiles = $videoFiles.Count
$totalOriginalSize = 0
$totalConvertedSize = 0
$failedConversions = @()
$successConversions = @()
$processedFiles = 0
$exitScript = $false
$startTime = Get-Date

$doBatching = $batchSize -gt 0
if ($doBatching) {
    $batches = [Math]::Ceiling($totalFiles / $batchSize)
    Write-Log "`nStarting HEVC conversion of $totalFiles files in $batches batches." -foregroundColor $infoColor
}
else {
    Write-Log "`nStarting HEVC conversion of $totalFiles files." -foregroundColor $infoColor
}
Write-Log "Using quality settings: CRF $crf, Preset $preset." -foregroundColor $infoColor

# Main loop for processing files (or batches)
for ($batchNumber = 1; ($processedFiles -lt $totalFiles) -and -not $exitScript; $batchNumber++) {
    if ($doBatching) {
        $currentBatch = $videoFiles | Select-Object -First $batchSize -Skip (($batchNumber - 1) * $batchSize)
        if (-not $currentBatch) { break } # Break if no files left in batch
        Write-Log "`nProcessing batch $batchNumber/$batches ($($currentBatch.Count) files)..." -foregroundColor $infoColor
        Write-Log ("-" * 80)
    }
    else {
        $currentBatch = $videoFiles
    }

    foreach ($file in $currentBatch) {
        $processedFiles++
        $fileStart = Get-Date
        $originalSize = $file.Length
        $totalOriginalSize += $originalSize

        $inputPath = $file.FullName
        $outputPath = Join-Path $outputFolder ($file.BaseName + "_x265.mkv")

        Write-Log "`n[$processedFiles/$totalFiles] Converting: $($file.Name) ($(Format-FileSize $originalSize))" -foregroundColor White
        Write-DebugInfo "Input path: $inputPath"
        Write-DebugInfo "Output path: $outputPath"
        Write-DebugInfo "Source size: $(Format-FileSize $originalSize)"

        # Gather media information
        $mediaInfo = Get-MediaInfo -filePath $inputPath
        if ($mediaInfo) {
            $width = [int]$mediaInfo.width
            $height = [int]$mediaInfo.height
            $duration = [double]$mediaInfo.duration
            Write-DebugInfo "Video codec: $($mediaInfo.codec_name), Resolution: ${width}x${height}"
            Write-DebugInfo "Pixel format: $($mediaInfo.pix_fmt), Duration: ${duration}s"
        }
        else {
            Write-Log "Failed to get media info for '$($file.Name)'. Skipping file." -foregroundColor $errorColor
            continue # Skip to the next file in the loop
        }

        $isOddWidth = ($width % 2) -ne 0
        $isOddHeight = ($height % 2) -ne 0

        if ($isOddWidth -or $isOddHeight) {
            Write-Log "Adjusting odd dimensions: ${width}x${height} -> $($width - $isOddWidth)x$($height - $isOddHeight)" -foregroundColor $warningColor
        }

        # Check for -WhatIf common parameter
        if ($PSCmdlet.ShouldProcess($file.Name, "Convert video to HEVC")) {
            try {
                # Build FFmpeg command
                $ffmpegParams = @(
                    "-stats",
                    "-y",
                    "-loglevel", "info",
                    "-i", $inputPath,
                    "-vf", "scale=$($width - $isOddWidth):$($height - $isOddHeight)"
                    "-map", "0:v:0",
                    "-map", "0:a?", 
                    "-map", "0:s?", 
                    "-map_chapters", "-1",
                    "-c:v", "libx265",
                    "-crf", "$crf",
                    "-preset", $preset,
                    "-c:a", "copy",
                    "-c:s", "copy",
                    "-x265-params", "log-level=error",
                    "-pix_fmt", "yuv420p10le",
                    "-tag:v", "hvc1",
                    $outputPath
                )

                Write-DebugInfo "Executing: ffmpeg $($ffmpegParams -join ' ')"
                $ffmpegOutput = & ffmpeg @ffmpegParams 2>&1

                # Check FFmpeg exit code
                if ($LASTEXITCODE -ne 0) {
                    throw "FFmpeg exited with error code $LASTEXITCODE"
                }
                if (-not (Test-Path $outputPath)) {
                    throw "Output file not created"
                }

                # Verify conversion
                $convertedFile = Get-Item $outputPath -ErrorAction Stop
                $convertedSize = $convertedFile.Length
                $totalConvertedSize += $convertedSize

                $sizeChangeAmount = [Math]::Abs($originalSize - $convertedSize)
                $compressionRatio = [Math]::Round(($convertedSize / $originalSize) * 100, 2)

                Write-Log "Converted size: $(Format-FileSize $convertedSize) ($compressionRatio% of original)" -foregroundColor $successColor
                if ($convertedSize -lt $originalSize) {
                    Write-Log "Size reduced by: $(Format-FileSize $sizeChangeAmount)" -foregroundColor $successColor
                }
                elseif ($convertedSize -gt $originalSize) {
                    Write-Log "Size increased by: $(Format-FileSize $sizeChangeAmount)" -foregroundColor $warningColor
                }
                else {
                    Write-Log "Size remained the same." -foregroundColor $infoColor
                }
                Write-Log "Conversion time: $((Get-Date).Subtract($fileStart).ToString('hh\:mm\:ss'))" -foregroundColor $infoColor

                # Move original file to the output folder
                Move-Item $inputPath $outputFolder -Force
                Write-Log "Original file moved to output folder." -foregroundColor $infoColor

                $successConversions += $file.Name
            }
            catch {
                $errorMsg = $_.Exception.Message
                Write-Log "Conversion failed: $errorMsg" -foregroundColor $errorColor

                # Save FFmpeg error log
                if ($ffmpegOutput) {
                    Write-Host "FFmpeg output:" -ForegroundColor $errorColor
                    $ffmpegOutput | ForEach-Object { 
                        Write-Host "  $_" -ForegroundColor $errorColor 
                    }
                    $logPath = Join-Path $failedFolder ($file.BaseName + ".log")
                    $ffmpegOutput | Out-File $logPath
                    Write-Log "FFmpeg error log saved to: $logPath" -foregroundColor $errorColor
                }

                # Move failed file to the 'failed' folder
                $failedPath = Join-Path -Path $failedFolder -ChildPath $file.Name
                try {
                    Move-Item $inputPath $failedPath -Force -ErrorAction Stop
                    Write-Log "Original file moved to failed folder." -foregroundColor $errorColor
                }
                catch {
                    Write-Log "Failed to move original file: $($_.Exception.Message)" -foregroundColor $errorColor
                }

                # Clean up partial output file if it exists
                if (Test-Path $outputPath) {
                    try {
                        Remove-Item $outputPath -Force -ErrorAction Stop
                        Write-Log "Deleted partial output file." -foregroundColor $warningColor
                    }
                    catch {
                        Write-Log "Failed to delete partial output: $($_.Exception.Message)" -foregroundColor $errorColor
                    }
                }
                $failedConversions += $file.Name
            }
        }
    }

    # Interactive prompt for batching
    if ($doBatching -and ($processedFiles -lt $totalFiles)) {
        Write-Log "`n"
        Write-Log ("-" * 80)
        Write-Log "Batch $batchNumber completed. Total processed: $processedFiles/$totalFiles." -foregroundColor $infoColor
        Write-Log "1) Continue processing next batch." -foregroundColor $successColor
        Write-Log "2) Exit script now." -foregroundColor $errorColor
        $choice = Read-Host "`nEnter your choice (1 or 2)"

        switch ($choice) {
            "1" { Write-Log "Continuing to next batch..." -foregroundColor $infoColor; Start-Sleep -Seconds 2 }
            "2" { Write-Log "Exiting script gracefully." -foregroundColor $warningColor; $exitScript = $true }
            default { Write-Log "Invalid selection. Exiting script gracefully." -foregroundColor $errorColor; $exitScript = $true }
        }
    }
}


# Generate summary
$totalTime = (Get-Date).Subtract($startTime)
$totalSavedSpaceAmount = [Math]::Abs($totalOriginalSize - $totalConvertedSize)
$avgFileTime = if ($processedFiles -gt 0) { $totalTime.TotalSeconds / $processedFiles } else { 0 } 

Write-Log "`n`n=================== CONVERSION SUMMARY ===================" -foregroundColor $infoColor
Write-Log "Total processed: $processedFiles" -foregroundColor White
Write-Log "Successful: $($successConversions.Count)" -foregroundColor $successColor
Write-Log "Failed: $($failedConversions.Count)" -foregroundColor $errorColor
Write-Log "Total time: $($totalTime.ToString('hh\:mm\:ss'))" -foregroundColor White
if ($successConversions.Count -gt 0) {
    Write-Log "Original size: $(Format-FileSize $totalOriginalSize)" -foregroundColor White
    Write-Log "Converted size: $(Format-FileSize $totalConvertedSize)" -foregroundColor White
    if ($totalOriginalSize -gt 0) {
        if ($totalConvertedSize -lt $totalOriginalSize) {
            Write-Log "Total space saved: $(Format-FileSize $totalSavedSpaceAmount)" -foregroundColor $successColor
        }
        elseif ($totalConvertedSize -gt $totalOriginalSize) {
            Write-Log "Total space increased: $(Format-FileSize $totalSavedSpaceAmount)" -foregroundColor $warningColor
        }
        else {
            Write-Log "Total space remained the same." -foregroundColor $infoColor
        }
        Write-Log "Converted size (% of original): $([Math]::Round(($totalConvertedSize / $totalOriginalSize) * 100, 2))%" -foregroundColor $infoColor
    }
    Write-Log "Average time/file: $([Math]::Round($avgFileTime, 1)) seconds"
    if ($totalTime.TotalHours -gt 0) {
        Write-Log "Processing rate: $([Math]::Round($processedFiles / $totalTime.TotalHours, 2)) files/hour"
        Write-Log "Processing speed: $([Math]::Round($totalOriginalSize / 1GB / $totalTime.TotalHours, 2)) GB/hour"
    }
    else {
        Write-Log "Processing rate: N/A (Total time too short)"
        Write-Log "Processing speed: N/A (Total time too short)"
    }
}
Write-Log "=======================================================`n" -foregroundColor $infoColor

if ($failedConversions) {
    Write-Log "Failed files:" -foregroundColor $errorColor
    $failedConversions | ForEach-Object { Write-Log "- $_" -foregroundColor $errorColor }
    Write-Log "Check the 'failed' folder for original files and error logs." -foregroundColor $errorColor
}

# Switch back to execution folder
Set-Location $PSScriptRoot
Write-DebugInfo "Script completed in $($totalTime.ToString('hh\:mm\:ss'))."

Read-Host "Press ENTER to exit..."
