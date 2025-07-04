<#
.SYNOPSIS
Converts video files to HEVC (H.265) format using FFmpeg with advanced options, batch processing, and robust error handling.

.DESCRIPTION
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

.PARAMETER Profile
Specifies a predefined encoding profile to use for conversion

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
Acceptable range is 0 (lossless) to 51 (lowest quality). Default is 28.

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
.\Convert-VideoToHEVC.ps1 -Profile Animation

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
    # predefined encoding profile
    [Parameter(HelpMessage = "Use a predefined encoding profile")]
    [ValidateSet("Animation", "Film", "ScreenCapture", "HighMotion", "LowLight", "ArchiveQuality", "MobileStream", "HDR-8K", "FilmRestoration", "SocialMedia")]
    [string]$Profile,

    # input & output folders
    [Parameter(HelpMessage = "Path to the folder containing video files to be converted.")]
    [string]$inputFolder = (Get-Location).Path,

    [Parameter(HelpMessage = "Path where converted HEVC video files will be saved.")]
    [string]$outputFolder = (Join-Path -Path (Get-Location).Path -ChildPath "converted"),

    # Advanced encoding parameters
    [Parameter(HelpMessage = "Number of files to process in each batch. Omit for no batching.")]
    [ValidateRange(0, 100)]
    [int]$batchSize = 0,

    [Parameter(HelpMessage = "Constant Rate Factor (CRF) value for libx265 encoding (0-51). Lower = higher quality.")]
    [ValidateRange(0, 51)]
    [int]$crf = 28,

    [Parameter(HelpMessage = "Encoding preset for libx265. Controls speed vs. compression efficiency.")]
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


# HELPER FUNCTIONS

<#
.SYNOPSIS
Loads an encoding profile from a JSON file.

.DESCRIPTION
Retrieves encoding settings from a predefined profile located in the 'Preset-Profiles'
subdirectory relative to the script's root. It handles cases where the profile file
doesn't exist or if there are issues parsing the JSON content.

.PARAMETER ProfileName
The name of the profile to load (e.g., "Animation" for "Animation.json").

.RETURNS
[PSObject] An object containing the profile's settings if successfully loaded;
otherwise, returns $null.

.NOTES
Assumes profile JSON files are located at `$PSScriptRoot\Preset-Profiles\$ProfileName.json`.
#>
function Get-EncodingProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProfileName
    )

    $profilePath = Join-Path -Path $PSScriptRoot -ChildPath "Preset-Profiles\$ProfileName.json"

    Write-DebugInfo "Attempting to load profile from: $profilePath"
    try {
        $profileContent = Get-Content $profilePath -Raw -ErrorAction Stop
        $profile = $profileContent | ConvertFrom-Json -ErrorAction Stop
        Write-Log "Successfully loaded profile: $($profile.name) - $($profile.description)" -foregroundColor $infoColor
        return $profile
    }
    catch [System.Management.Automation.JsonException] { # Catch specific JSON parsing errors
        Write-Log "Error parsing JSON for profile '$ProfileName': $($_.Exception.Message)" -foregroundColor $errorColor
        Write-DebugInfo "Raw profile content that failed to parse: `n$profileContent"
        return $null
    }
    catch {
        Write-Log "An unexpected error occurred while loading profile '$ProfileName': $($_.Exception.Message)" -foregroundColor $errorColor
        return $null
    }
}


<#
.SYNOPSIS
Writes formatted log messages to console and optionally to a file.

.DESCRIPTION
Outputs messages with timestamp and color coding. Can write to both console and log file.

.PARAMETER Message
The message to log.

.PARAMETER ForegroundColor 
Console text color (default: White).
#>
function Write-Log {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [string]$ForegroundColor  = "White"
    )

    # Output to console
    Write-Host $Message -ForegroundColor $ForegroundColor

    # Output to log file if enabled
    if ($LogToFile) {
        try {
            $timestampedMessage = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
            Add-Content -Path $logFilePath -Value $timestampedMessage -ErrorAction Stop
        }
        catch {
            Write-Host "WARNING: Failed to write to log file '$logFilePath'. Error: $($_.Exception.Message)" -ForegroundColor $warningColor
        }
    }
}


<#
.SYNOPSIS
Outputs debug messages when DebugMode is enabled.

.DESCRIPTION
This function serves as a conditional logger for debug information. Messages are only
displayed on the console and written to the log file if the `$DebugMode` switch
parameter in the main script is set to $true. Debug messages are timestamped
with millisecond precision and appear in a distinct magenta color.

.PARAMETER Message
The debug message string to be logged. This parameter is mandatory.

.EXAMPLE
Write-DebugInfo "Variable value: $myVariable"
#>
function Write-DebugInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )
    if ($DebugMode) {
        Write-Log "[DEBUG] $(Get-Date -Format 'HH:mm:ss.fff') - $Message" -foregroundColor $debugColor
    }
}


<#
.SYNOPSIS
Formats a given file size in bytes into a human-readable string.

.DESCRIPTION
Converts a byte count into a more understandable format, displaying it in
Terabytes (TB), Gigabytes (GB), Megabytes (MB), Kilobytes (KB), or bytes,
whichever is most appropriate.

.PARAMETER Size
The file size value, specified in bytes. This parameter expects a long integer.

.RETURNS
[string] A formatted string representing the file size (e.g., "1.23 GB").

.EXAMPLE
Format-FileSize -Size 1024
# Output: 1.00 KB

.EXAMPLE
Format-FileSize -Size 1073741824
# Output: 1.00 GB
#>
function Format-FileSize {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [long]$Size
    )
    process {
        switch ($Size) {
            { $_ -ge 1TB } { "{0:N2} TB" -f ($_ / 1TB); break }
            { $_ -ge 1GB } { "{0:N2} GB" -f ($_ / 1GB); break }
            { $_ -ge 1MB } { "{0:N2} MB" -f ($_ / 1MB); break }
            { $_ -ge 1KB } { "{0:N2} KB" -f ($_ / 1KB); break }
            default { "$_ bytes" }
        }
    }
}


<#
.SYNOPSIS
Verifies the availability and capabilities of FFmpeg and FFprobe.

.DESCRIPTION
This function performs several checks to ensure that FFmpeg and FFprobe are correctly
installed and accessible in the system's PATH environment variable. It also confirms
the presence of the 'libx265' encoder (for HEVC support) and identifies any available
hardware acceleration methods (e.g., CUDA, NVENC, QSV). Detailed logs are generated
for each check.

.RETURNS
[bool] Returns $true if all necessary FFmpeg/FFprobe components are verified and
HEVC encoding is supported; otherwise, returns $false.

.NOTES
Requires 'ffmpeg.exe' and 'ffprobe.exe' binaries to be present in an accessible PATH.
Provides specific error messages if components are missing or if libx265 is not found.
#>
function Test-FFmpeg {
    [CmdletBinding()]
    param() # No parameters for this function

    Write-DebugInfo "Initiating FFmpeg and FFprobe system checks..."

    # Define common executable names
    $ffmpegExe = "ffmpeg"
    $ffprobeExe = "ffprobe"

    try {
        # --- 1. Test FFmpeg basic execution and version ---
        Write-DebugInfo "Testing FFmpeg command existence..."
        $ffmpegOutput = & $ffmpegExe -version 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0 -or -not ($ffmpegOutput -match 'ffmpeg version')) {
            Write-Log "FFmpeg test failed! '$ffmpegExe' command not found or returned an error." -foregroundColor $errorColor
            Write-Log "Please ensure FFmpeg is installed and its directory is in your system's PATH." -foregroundColor $errorColor
            return $false
        }
        $ffmpegVersion = ($ffmpegOutput | Select-String -Pattern 'ffmpeg version').Line.Split()[2]
        Write-Log "FFmpeg version: $ffmpegVersion" -foregroundColor $infoColor

        # --- 2. Test FFprobe basic execution and version ---
        Write-DebugInfo "Testing FFprobe command existence..."
        $ffprobeOutput = & $ffprobeExe -version 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0 -or -not ($ffprobeOutput -match 'ffprobe version')) {
            Write-Log "FFprobe test failed! '$ffprobeExe' command not found or returned an error." -foregroundColor $errorColor
            Write-Log "Please ensure FFprobe is installed and its directory is in your system's PATH." -foregroundColor $errorColor
            return $false
        }
        $ffprobeVersion = ($ffprobeOutput | Select-String -Pattern 'ffprobe version').Line.Split()[2]
        Write-Log "FFprobe version: $ffprobeVersion" -foregroundColor $infoColor

        # --- 3. Check for libx265 encoder ---
        Write-DebugInfo "Checking for libx265 encoder support..."
        $x265EncoderInfo = & $ffmpegExe -encoders 2>&1 | Select-String -Pattern 'libx265'
        if (-not $x265EncoderInfo) {
            Write-Log "HEVC encoder ('libx265') not found in FFmpeg. This build cannot encode HEVC." -foregroundColor $errorColor
            Write-Log "Please download an FFmpeg build that includes libx265 (e.g., from gyan.dev or official sources)." -foregroundColor $errorColor
            return $false
        }
        Write-Log "HEVC encoder (libx265): Available" -foregroundColor $successColor

        # --- 4. Check for hardware acceleration support ---
        Write-DebugInfo "Detecting hardware acceleration methods..."
        $hwaccelInfo = & $ffmpegExe -hwaccels 2>&1 | Out-String
        $hwaccelsFound = @()

        # Regex to find common hardware acceleration methods
        $pattern = "(?i)\b(?:cuda|nvenc|qsv|amf|vdpau|d3d11va|videotoolbox|libmfx)\b"
        $matches = [regex]::Matches($hwaccelInfo, $pattern)
        
        foreach ($match in $matches) {
            $hwaccelsFound += $match.Value # Add matched string (e.g., "cuda", "qsv")
        }
        
        $hwaccelsFound = $hwaccelsFound | Select-Object -Unique

        if ($hwaccelsFound.Count -gt 0) {
            Write-Log "Detected hardware acceleration: $($hwaccelsFound -join ', ')" -foregroundColor $infoColor
        } else {
            Write-Log "No common hardware acceleration methods detected (e.g., CUDA, NVENC, QSV)." -foregroundColor $warningColor
            Write-Log "Conversion will proceed using CPU, which may be slower." -foregroundColor $warningColor
        }

        Write-Log "All FFmpeg/FFprobe requirements met." -foregroundColor $successColor
        return $true
    }
    catch {
        Write-Log "An unhandled error occurred during FFmpeg/FFprobe checks: $($_.Exception.Message)" -foregroundColor $errorColor
        Write-Log "Ensure your PATH environment variable is correctly configured and permissions allow execution." -foregroundColor $errorColor
        return $false
    }
}


<#
.SYNOPSIS
Retrieves essential media information from a video file using FFprobe.

.DESCRIPTION
This function executes 'ffprobe' to extract specific metadata about the primary
video stream, including codec name, resolution, pixel format, duration, and bitrate.
It is designed to handle various FFprobe output scenarios, including non-existent files,
execution errors, and invalid JSON output.

.PARAMETER FilePath
The full path to the media file for which information is to be retrieved.
This parameter is mandatory.

.RETURNS
[PSObject] An object containing the parsed media stream information (e.g.,
'codec_name', 'width', 'height', 'duration', 'bit_rate'); returns $null on failure.

.NOTES
Requires 'ffprobe.exe' to be installed and accessible via the system's PATH.
Designed to be robust against common FFprobe execution and parsing issues.
#>
function Get-MediaInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    Write-DebugInfo "Attempting to get media info for: $FilePath"

    if (-not (Test-Path $FilePath -PathType Leaf)) {
        Write-Log "Input file '$FilePath' not found for media info extraction." -foregroundColor $script:errorColor
        Write-DebugInfo "Test-Path check failed for: $FilePath"
        return $null
    }

    try {
        $ffprobeParams = @(
            "-v", "error",
            "-select_streams", "v:0",
            "-show_entries", "stream=codec_name,width,height,pix_fmt,duration,bit_rate",
            "-of", "json",
            $FilePath
        )

        Write-DebugInfo "Executing ffprobe: ffprobe $($ffprobeParams -join ' ')"

        # Execute ffprobe and capture output
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = "ffprobe"
        $processInfo.Arguments = $ffprobeParams -join ' '
        $processInfo.RedirectStandardOutput = $true
        $processInfo.RedirectStandardError = $true
        $processInfo.UseShellExecute = $false
        $processInfo.CreateNoWindow = $true

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $processInfo
        $process.Start() | Out-Null

        $ffprobeStdOut = $process.StandardOutput.ReadToEnd()
        $ffprobeStdErr = $process.StandardError.ReadToEnd()

        $process.WaitForExit()

        if ($process.ExitCode -ne 0) {
            Write-Log "FFprobe failed for '$FilePath' with exit code $($process.ExitCode)." -foregroundColor $script:errorColor
            Write-DebugInfo "FFprobe StdErr for '$FilePath': `n$ffprobeStdErr"
            Write-DebugInfo "FFprobe StdOut (if any) for '$FilePath': `n$ffprobeStdOut"
            return $null
        }

        $ffprobeOutputString = $ffprobeStdOut.Trim()

        # Basic JSON format validation
        if (-not ($ffprobeOutputString.StartsWith("{") -and $ffprobeOutputString.EndsWith("}"))) {
            Write-Log "FFprobe returned invalid or no JSON output for '$FilePath'." -foregroundColor $script:errorColor
            Write-DebugInfo "FFprobe raw output for '$FilePath': `n$ffprobeOutputString"
            Write-DebugInfo "FFprobe StdErr (if any) for '$FilePath': `n$ffprobeStdErr"
            return $null
        }

        # Attempt to parse JSON
        $mediaInfo = $ffprobeOutputString | ConvertFrom-Json -ErrorAction Stop

        # Validate parsed object structure
        if ($null -eq $mediaInfo -or $null -eq $mediaInfo.streams -or $mediaInfo.streams.Count -eq 0) {
            Write-Log "Could not find video stream information in FFprobe output for '$FilePath'." -foregroundColor $script:errorColor
            Write-DebugInfo "Parsed FFprobe object structure: $($mediaInfo | ConvertTo-Json -Depth 3)"
            return $null
        }

        Write-DebugInfo "Successfully retrieved media info for '$FilePath'."
        return $mediaInfo.streams[0]
    }
    catch [System.Management.Automation.JsonException] {
        Write-Log "Failed to parse FFprobe JSON for '$FilePath': $($_.Exception.Message)" -foregroundColor $script:errorColor
        Write-DebugInfo "JSON parsing error details: $($_.Exception.InnerException.Message)"
        return $null
    }
    catch {
        Write-Log "An unexpected error occurred during Get-MediaInfo for '$FilePath': $($_.Exception.Message)" -foregroundColor $script:errorColor
        Write-DebugInfo "Detailed error: $($_.Exception | Format-List -Force)"
        return $null
    }
}


# MAIN SCRIPT EXECUTION

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

# Initialize logging
if ($LogToFile) {
    Write-Host "Creating log file: $logFilePath" -ForegroundColor Gray
    Add-Content -Path $logFilePath -Value "Conversion log started at $(Get-Date)`n"
}

# Validate FFmpeg
if (-not (Test-FFmpeg)) {
    exit 1
}

# Load encoding profile if specified
$encodingProfile = $null
if ($Profile) {
    $encodingProfile = Get-EncodingProfile $Profile
    if ($encodingProfile) {
        # Only apply profile settings if user didn't explicitly provide the parameter
        if (-not $PSBoundParameters.ContainsKey('crf') -and $encodingProfile.crf) { 
            $crf = $encodingProfile.crf
        }
        if (-not $PSBoundParameters.ContainsKey('preset') -and $encodingProfile.preset) { 
            $preset = $encodingProfile.preset
        }
    }
}

# Validate and create folders
try {
    Write-DebugInfo "Validating folder structure..."

    # Create output folder if needed
    if (-not (Test-Path -Path $outputFolder -PathType Container)) {
        Write-Log "Creating output folder: $outputFolder" -foregroundColor $infoColor
        $null = New-Item -ItemType Directory -Path $outputFolder -Force
    }

    # Create failed folder if needed
    $failedFolder = Join-Path -Path $inputFolder -ChildPath "failed"
    if (-not (Test-Path -Path $failedFolder -PathType Container)) {
        Write-Log "Creating failed items folder: $failedFolder" -foregroundColor $infoColor
        $null = New-Item -ItemType Directory -Path $failedFolder -Force
    }

    # Verify write permissions
    $testFile = Join-Path -Path $outputFolder -ChildPath "write_test"
    try {
        $null = New-Item -ItemType File -Path $testFile -Force -ErrorAction Stop
        Remove-Item -Path $testFile -Force -ErrorAction Stop
    }
    catch {
        throw "No write permission in output folder: $outputFolder"
    }
}
catch {
    Write-Log "Failed to initialize folder structure. Details: $_" -foregroundColor $errorColor
    exit 1
}

# Set working directory
try {
    Set-Location -Path $inputFolder -ErrorAction Stop
    Write-DebugInfo "Working directory set to: $(Get-Location)"
}
catch {
    Write-Log "Failed to access input folder. Details: $_" -foregroundColor $errorColor
    exit 1
}

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
    Write-Log "Failed to process input folder: $inputFolder. Details: $_" -foregroundColor $errorColor
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
$totalOriginalSize = 0 # Size of original files that were SUCCESSFULLY converted
$totalConvertedSize = 0 # Size of converted files that were SUCCESSFULLY converted
$failedConversions = @()
$successConversions = @()
$processedFiles = 0
$exitScript = $false
$startTime = Get-Date

# Initialize batch processing
$doBatching = $batchSize -gt 0
if ($doBatching) {
    $batches = [Math]::Ceiling($totalFiles / $batchSize)
    Write-Log "`nStarting HEVC conversion of $totalFiles files in $batches batches." -foregroundColor $infoColor
}
else {
    Write-Log "`nStarting HEVC conversion of $totalFiles files." -foregroundColor $infoColor
}

# Show profile info if used
if ($encodingProfile) {
    Write-Log "Using profile: $($encodingProfile.name) - $($encodingProfile.description)" -foregroundColor $infoColor
}
Write-Log "Quality settings: CRF $crf, Preset $preset." -foregroundColor $infoColor

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
                    "-loglevel", "info", # Keep loglevel info for ffmpeg progress info
                    "-i", $inputPath,
                    # Apply resolution adjustment if needed
                    if ($isOddWidth -or $isOddHeight) { "-vf", "scale=$($width - $isOddWidth):$($height - $isOddHeight)" } else { $null },
                    "-map", "0:v:0", # Map only the first video stream
                    "-map", "0:a?", # Map all audio streams if they exist
                    "-map", "0:s?", # Map all subtitle streams if they exist
                    "-map_chapters", "-1", # Do not copy chapters
                    "-c:v", "libx265",
                    "-crf", "$crf",
                    "-preset", $preset
                )

                # Add profile-specific parameters
                if ($encodingProfile -and $encodingProfile.extra_params) {
                    Write-DebugInfo "Adding profile parameters: $($encodingProfile.extra_params -join ' ')"
                    $ffmpegParams += $encodingProfile.extra_params
                }

                # Add standard parameters
                $ffmpegParams += @(
                    "-c:a", "copy",
                    "-c:s", "copy",
                    "-x265-params", "log-level=error",
                    "-pix_fmt", "yuv420p10le",
                    "-tag:v", "hvc1", # Ensure proper tag for HEVC
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
                $totalOriginalSize += $originalSize
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
                Write-Log "Conversion failed for '$($file.Name)': $errorMsg" -foregroundColor $errorColor

                # Output full FFmpeg log to console on failure
                if ($ffmpegOutput.Count -gt 0) {
                    Write-Host "--- FFmpeg Error Output for '$($file.Name)' ---" -ForegroundColor $errorColor
                    $ffmpegOutput | ForEach-Object { 
                        Write-Host "   $_" -ForegroundColor $errorColor 
                    }
                    Write-Host "----------------------------------------------" -ForegroundColor $errorColor
                }

                # Save FFmpeg error log to file
                if ($ffmpegOutput.Count -gt 0) {
                    $logPath = Join-Path $failedFolder ($file.BaseName + ".log")
                    $ffmpegOutput | Out-File $logPath
                    Write-Log "FFmpeg error log saved to: $logPath" -foregroundColor $errorColor
                }
                else {
                    Write-Log "No specific FFmpeg output captured for error, check general script log." -foregroundColor $warningColor
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
        Write-Log "Batch $batchNumber/$batches completed. Total processed: $processedFiles/$totalFiles." -foregroundColor $infoColor
        Write-Log "Remaining files: $($totalFiles - $processedFiles)" -foregroundColor $infoColor

        $options = @{
            'c' = "Continue processing next batch."
            'x' = "Exit script now."
        }

        $prompt = "`nChoose an option:`n"
        $options.Keys | ForEach-Object { $prompt += "[$_] $($options.$_)`n" }
        $prompt += "Enter your choice: "

        $choice = Read-Host -Prompt $prompt

        switch ($choice) {
            "1" { Write-Log "Continuing to next batch..." -foregroundColor $infoColor; Start-Sleep -Seconds 1 }
            "2" { Write-Log "Exiting script gracefully." -foregroundColor $warningColor; $exitScript = $true }
            default { Write-Log "Invalid selection. Exiting script gracefully." -foregroundColor $errorColor; $exitScript = $true }
        }
    }
}


# Generate summary report
$totalTime = (Get-Date).Subtract($startTime)

Write-Log "`n`n=================== CONVERSION SUMMARY ===================" -foregroundColor $infoColor
Write-Log "Total input files: $totalFiles" -foregroundColor White
Write-Log "Total files processed: $processedFiles" -foregroundColor White
Write-Log "Successful conversions: $($successConversions.Count)" -foregroundColor $successColor
Write-Log "Failed conversions: $($failedConversions.Count)" -foregroundColor $errorColor
Write-Log "Total runtime: $($totalTime.ToString('hh\:mm\:ss'))" -foregroundColor White

if ($successConversions.Count -gt 0) { 
    $compressionRatio = $([Math]::Round(($totalConvertedSize / $totalOriginalSize) * 100, 2))
    $spaceSaved = [Math]::Abs($totalOriginalSize - $totalConvertedSize)
    $avgFileTime = if ($processedFiles -gt 0) { $totalTime.TotalSeconds / $processedFiles } else { 0 } 

    Write-Log "Original size: $(Format-FileSize $totalOriginalSize)" -foregroundColor White
    Write-Log "Converted size: $(Format-FileSize $totalConvertedSize)" -foregroundColor White
    Write-Log "Overall compression ratio: $compressionRatio%" -foregroundColor $infoColor

    if ($spaceSaved -ge 0) {
        Write-Log "Total space saved: $(Format-FileSize $spaceSaved)" -foregroundColor $successColor
    }
    else {
        Write-Log "Total space increased: $(Format-FileSize $spaceSaved)" -foregroundColor $warningColor
    }

    Write-Log "Average time per conversion: $([Math]::Round($avgFileTime, 1)) seconds"
    # To calculate files/hour and GB/hour, ensure TotalHours is not zero
    if ($totalTime.TotalHours -gt 0) {
        $filesPerHour = [Math]::Round($successConversions.Count / $totalTime.TotalHours, 2)
        $gbPerHour = [Math]::Round($totalOriginalSize / 1GB / $totalTime.TotalHours, 2)
        Write-Log "Processing rate: $filesPerHour files/hour"
        Write-Log "Processing speed: $gbPerHour GB/hour"
    }
}
else {
    Write-Log "No successful conversions to report size and speed statistics." -foregroundColor $warningColor
}
Write-Log "=======================================================`n" -foregroundColor $infoColor

if ($failedConversions.Count -gt 0) {
    Write-Log "Failed files:" -foregroundColor $errorColor
    $failedConversions | ForEach-Object { Write-Log "- $_" -foregroundColor $errorColor }
    Write-Log "Check the 'failed' folder for original files and error logs." -foregroundColor $errorColor
}

# Switch back to execution folder
Set-Location $PSScriptRoot
Write-DebugInfo "Script completed in $($totalTime.ToString('hh\:mm\:ss'))."

Read-Host "Press ENTER to exit..."
