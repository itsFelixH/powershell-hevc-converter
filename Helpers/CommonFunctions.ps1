# CommonFunctions.ps1
# This file contains shared helper functions used by both Convert-VideoToHEVC.ps1
# and Optimize-HEVCSettings.ps1.

# Global script-scoped variables for logging colors and path.
# These are expected to be defined in the main script that dot-sources this file,
# and then linked to the $script: scope here for consistent access.
$script:successColor = $script:successColor -or "Green"
$script:warningColor = $script:warningColor -or "Yellow"
$script:errorColor = $script:errorColor -or "Red"
$script:infoColor = $script:infoColor -or "Cyan"
$script:debugColor = $script:debugColor -or "Magenta"
$script:logFilePath = $script:logFilePath -or $null # This will be set by the main script
$script:LogToFile = $script:LogToFile -or $false
$script:DebugMode = $script:DebugMode -or $false


<#
.SYNOPSIS
Writes formatted log messages to the console and, optionally, to a dedicated log file.

.DESCRIPTION
This function outputs messages with a timestamp and applies color coding to the console output.
If the `$LogToFile` switch is enabled in the main script, all messages are also appended
to the global log file specified by `$logFilePath`. Includes error handling for file writes.

.PARAMETER Message
The string message to be logged. This parameter is mandatory.

.PARAMETER ForegroundColor
Specifies the console text color for the message. This should be a valid PowerShell color name
(e.g., "Green", "Red", "Cyan"). Defaults to "White".

.EXAMPLE
Write-Log "Starting conversion process..." -ForegroundColor "Green"

.EXAMPLE
Write-Log "File not found: C:\video.mp4" -ForegroundColor "Red"
#>
function Write-Log {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [string]$ForegroundColor = "White" # Default to White
    )

    # Output to console
    Write-Host $Message -ForegroundColor $ForegroundColor

    # Output to log file if enabled. Use $script: scope for variables from the main script.
    if ($script:LogToFile) {
        try {
            $timestampedMessage = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
            # Ensure the directory exists before attempting to write the file
            $logFileDirectory = Split-Path -Path $script:logFilePath -Parent
            if (-not (Test-Path $logFileDirectory -PathType Container)) {
                New-Item -ItemType Directory -Path $logFileDirectory -Force | Out-Null
            }
            Add-Content -Path $script:logFilePath -Value $timestampedMessage -ErrorAction Stop
        }
        catch {
            # This catch block is specifically for errors writing to the log file itself,
            # to prevent a logging failure from crashing the entire script.
            Write-Host "WARNING: Failed to write to log file '$script:logFilePath'. Error: $($_.Exception.Message)" -ForegroundColor $script:warningColor
            # Avoid infinite recursion if Write-Log itself fails during logging an error.
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
    if ($script:DebugMode) { # Use script: scope for the parameter
        Write-Log "[DEBUG] $(Get-Date -Format 'HH:mm:ss.fff') - $Message" -foregroundColor $script:debugColor
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
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)] # Can accept pipeline input
        [long]$Size
    )
    process { # Use 'process' block for pipeline support
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

    # Use $PSScriptRoot to ensure path is relative to the script
    # $PSScriptRoot is the directory of the script that *dot-sourced* this file.
    $profilePath = Join-Path -Path $PSScriptRoot -ChildPath "Preset-Profiles\$ProfileName.json"

    Write-DebugInfo "Attempting to load profile from: $profilePath"

    if (-not (Test-Path $profilePath -PathType Leaf)) {
        Write-Log "Profile '$ProfileName' not found at '$profilePath'. Using default encoding settings." -foregroundColor $script:warningColor
        return $null
    }

    try {
        $profileContent = Get-Content $profilePath -Raw -ErrorAction Stop
        $profile = $profileContent | ConvertFrom-Json -ErrorAction Stop
        Write-Log "Successfully loaded profile: $($profile.name) - $($profile.description)" -foregroundColor $script:infoColor
        return $profile
    }
    catch [System.Management.Automation.JsonException] { # Catch specific JSON parsing errors
        Write-Log "Error parsing JSON for profile '$ProfileName': $($_.Exception.Message)" -foregroundColor $script:errorColor
        Write-DebugInfo "Raw profile content that failed to parse: `n$profileContent"
        return $null
    }
    catch { # Catch any other unexpected errors during file reading
        Write-Log "An unexpected error occurred while loading profile '$ProfileName': $($_.Exception.Message)" -foregroundColor $script:errorColor
        return $null
    }
}


<#
.SYNOPSIS
Verifies the availability and capabilities of FFmpeg and FFprobe.

.DESCRIPTION
This function performs several checks to ensure that FFmpeg and FFprobe are correctly
installed and accessible in the system's PATH environment variable. It also confirms
the presence of the 'libx265' encoder (for HEVC support) and identifies any available
hardware acceleration methods. It also checks for the presence of the VMAF model file.

.RETURNS
[bool] Returns $true if all FFmpeg/FFprobe requirements and VMAF model are met, otherwise $false.

.NOTES
Requires 'ffmpeg.exe' and 'ffprobe.exe' binaries to be present in an accessible PATH.
Provides specific error messages if components are missing or if libx265 is not found.
Assumes VMAF model is located in a 'VMAF-Models' subdirectory relative to the script's root.
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
        $ffmpegOutput = (ffmpeg -version 2>&1) | Out-String
        if ($LASTEXITCODE -ne 0 -or -not ($ffmpegOutput -match 'ffmpeg version')) {
            Write-Log "FFmpeg test failed! '$ffmpegExe' command not found or returned an error." -foregroundColor $script:errorColor
            Write-Log "Please ensure FFmpeg is installed and its directory is in your system's PATH." -foregroundColor $script:errorColor
            return $false
        }
        $ffmpegVersion = ($ffmpegOutput | Select-String -Pattern 'ffmpeg version').Line.Split()[2]
        Write-Log "FFmpeg version: $ffmpegVersion" -foregroundColor $script:infoColor

        # --- 2. Test FFprobe basic execution and version ---
        Write-DebugInfo "Testing FFprobe command existence..."
        $ffprobeOutput = (ffprobe -version 2>&1) | Out-String
        if ($LASTEXITCODE -ne 0 -or -not ($ffprobeOutput -match 'ffprobe version')) {
            Write-Log "FFprobe test failed! '$ffprobeExe' command not found or returned an error." -foregroundColor $script:errorColor
            Write-Log "Please ensure FFprobe is installed and its directory is in your system's PATH." -foregroundColor $script:errorColor
            return $false
        }
        $ffprobeVersion = ($ffprobeOutput | Select-String -Pattern 'ffprobe version').Line.Split()[2]
        Write-Log "FFprobe version: $ffprobeVersion" -foregroundColor $script:infoColor

        # --- 3. Check for libx265 encoder ---
        Write-DebugInfo "Checking for libx265 encoder support..."
        $x265EncoderInfo = & $ffmpegExe -encoders 2>&1 | Select-String -Pattern 'libx265'
        if (-not $x265EncoderInfo) {
            Write-Log "HEVC encoder ('libx265') not found in FFmpeg. This build cannot encode HEVC." -foregroundColor $script:errorColor
            Write-Log "Please download an FFmpeg build that includes libx265 (e.g., from gyan.dev or official sources)." -foregroundColor $script:errorColor
            return $false
        }
        Write-Log "HEVC encoder (libx265): Available" -foregroundColor $script:successColor

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

        $hwaccelsFound = $hwaccelsFound | Select-Object -Unique # Remove duplicates

        if ($hwaccelsFound.Count -gt 0) {
            Write-Log "Detected hardware acceleration: $($hwaccelsFound -join ', ')" -foregroundColor $script:infoColor
        } else {
            Write-Log "No common hardware acceleration methods detected (e.g., CUDA, QSV, NVENC)." -foregroundColor $script:warningColor
            Write-Log "Conversion will proceed using CPU, which may be slower." -foregroundColor $script:warningColor
        }

        # --- 5. Check for VMAF model file ---
        # $PSScriptRoot is the directory of the script that *dot-sourced* this file (e.g., Convert-VideoToHEVC.ps1)
        # So, the VMAF-Models directory is one level up from the Helpers directory.
        $vmafModelDirectory = Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath "VMAF-Models"
        $vmafModelPath = Join-Path -Path $vmafModelDirectory -ChildPath "vmaf_v0.6.1.json"

        Write-DebugInfo "Checking for VMAF model at: $vmafModelPath"
        if (-not (Test-Path $vmafModelPath -PathType Leaf)) {
            Write-Log "VMAF model 'vmaf_v0.6.1.json' not found at '$vmafModelPath'." -foregroundColor $script:errorColor
            Write-Log "The Optimize-HEVCSettings.ps1 script requires this for quality analysis." -foregroundColor $script:errorColor
            return $false
        }
        Write-Log "VMAF model found." -foregroundColor $script:successColor


        Write-Log "All FFmpeg/FFprobe requirements met." -foregroundColor $script:successColor
        return $true
    }
    catch {
        # Catch any unexpected errors that occurred during the execution of external commands
        Write-Log "An unhandled error occurred during FFmpeg/FFprobe checks: $($_.Exception.Message)" -foregroundColor $script:errorColor
        Write-Log "Ensure your PATH environment variable is correctly configured and permissions allow execution." -foregroundColor $script:errorColor
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
            "-v", "error", # Only show errors from ffprobe itself
            "-select_streams", "v:0", # Select the first video stream
            "-show_entries", "stream=codec_name,width,height,pix_fmt,duration,bit_rate",
            "-of", "json",
            $FilePath
        )

        Write-DebugInfo "Executing ffprobe: ffprobe $($ffprobeParams -join ' ')"

        # Execute ffprobe and capture output
        # Using a process object to capture stderr reliably in case of issues
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

        # Check exit code first
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
        return $mediaInfo.streams[0] # Return the first video stream object
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


<#
.SYNOPSIS
Retrieves the total duration of a media file using FFprobe.

.DESCRIPTION
This function uses FFprobe to extract the duration of a video or audio file.
It attempts to get the duration from the format section of the FFprobe output,
which is generally reliable.

.PARAMETER FilePath
The full path to the media file for which the duration is to be retrieved.
This parameter is mandatory.

.RETURNS
[TimeSpan] A TimeSpan object representing the media's duration, or $null on failure.

.NOTES
Requires 'ffprobe.exe' to be installed and accessible via the system's PATH.
Handles cases where duration might not be directly available or parsing fails.
#>
function Get-MediaDuration {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    Write-DebugInfo "Getting duration for: $FilePath"

    if (-not (Test-Path $FilePath -PathType Leaf)) {
        Write-Log "Input file '$FilePath' not found for duration extraction." -foregroundColor $script:errorColor
        Write-DebugInfo "Test-Path check failed for: $FilePath"
        return $null
    }

    try {
        # Use ffprobe to get duration from the format section in JSON format
        $ffprobeOutput = & ffprobe -v error -show_entries format=duration -of json "$FilePath" 2>&1 | ConvertFrom-Json

        if ($null -ne $ffprobeOutput -and $null -ne $ffprobeOutput.format -and $null -ne $ffprobeOutput.format.duration) {
            # Convert duration (which is a string or float in seconds) to a TimeSpan object
            $durationSeconds = [double]$ffprobeOutput.format.duration
            $duration = [TimeSpan]::FromSeconds($durationSeconds)
            Write-DebugInfo "Raw duration for $FilePath: $durationSeconds seconds."
            return $duration
        } else {
            Write-Log "Could not retrieve duration for $FilePath from format section." -foregroundColor $script:warningColor
            Write-DebugInfo "FFprobe output for duration: $($ffprobeOutput | ConvertTo-Json -Depth 2)"
            return $null
        }
    }
    catch [System.Management.Automation.JsonException] {
        Write-Log "Failed to parse FFprobe JSON for duration of '$FilePath': $($_.Exception.Message)" -foregroundColor $script:errorColor
        Write-DebugInfo "JSON parsing error details: $($_.Exception.InnerException.Message)"
        return $null
    }
    catch {
        Write-Log "An unexpected error occurred during Get-MediaDuration for '$FilePath': $($_.Exception.Message)" -foregroundColor $script:errorColor
        Write-DebugInfo "Detailed error: $($_.Exception | Format-List -Force)"
        return $null
    }
}


<#
.SYNOPSIS
Formats a TimeSpan object into a human-readable HH:mm:ss string.

.DESCRIPTION
Converts a TimeSpan object into a string representation in the format
HH:mm:ss. If the duration includes days, it will prepend the number of days.

.PARAMETER TimeSpanObject
The TimeSpan object to format. This parameter is mandatory and accepts pipeline input.

.RETURNS
[string] A formatted string representing the TimeSpan (e.g., "01:23:45" or "2d 01:23:45").

.EXAMPLE
$ts = New-TimeSpan -Hours 1 -Minutes 30 -Seconds 15
Format-TimeSpanForDisplay -TimeSpanObject $ts
# Output: 01:30:15

.EXAMPLE
(New-TimeSpan -Days 2 -Hours 5 -Minutes 0 -Seconds 30) | Format-TimeSpanForDisplay
# Output: 2d 05:00:30
#>
function Format-TimeSpanForDisplay {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [TimeSpan]$TimeSpanObject
    )
    process {
        if ($TimeSpanObject.Days -gt 0) {
            # Use TotalHours for hours if days are present, to avoid 24-hour cycle reset
            $totalHours = [Math]::Floor($TimeSpanObject.TotalHours)
            return "{0}d {1:00}:{2:mm}:{3:ss}" -f $TimeSpanObject.Days, $totalHours, $TimeSpanObject.Minutes, $TimeSpanObject.Seconds
        } else {
            return $TimeSpanObject.ToString('hh\:mm\:ss')
        }
    }
}


<#
.SYNOPSIS
Creates a temporary file with a unique name and specified extension.

.DESCRIPTION
Generates a unique temporary file path using .NET methods and then changes its
extension to the desired format. The initial .tmp file created by GetTempFileName()
is immediately removed, and only the path with the new extension is returned.

.PARAMETER Extension
The desired file extension for the temporary file (e.g., ".mp4", ".log", ".json").
Defaults to ".tmp".

.RETURNS
[string] The full path to the newly generated temporary file.

.NOTES
The file itself is not created by this function; only its unique path is generated.
The caller is responsible for creating and cleaning up the file content.
#>
function New-TempFile {
    [CmdletBinding()]
    param(
        [string]$Extension = ".tmp"
    )
    $tempFileName = [System.IO.Path]::GetTempFileName()
    Remove-Item $tempFileName -ErrorAction SilentlyContinue # Delete the .tmp file created by GetTempFileName()
    $finalTempPath = [System.IO.Path]::ChangeExtension($tempFileName, $Extension)
    Write-DebugInfo "Generated temporary file path: $finalTempPath"
    return $finalTempPath
}


<#
.SYNOPSIS
Retrieves the number of logical processor cores available on the system.

.DESCRIPTION
This function attempts to get the total number of logical processor cores
using WMI (Win32_Processor). If WMI fails or is unavailable, it falls back
to using .NET's Environment.ProcessorCount. This is useful for
determining optimal threading for applications like FFmpeg/VMAF.

.RETURNS
[int] The total number of logical processor cores.

.NOTES
This counts logical processors (which includes hyper-threading cores).
#>
function Get-ProcessorCount {
    [CmdletBinding()]
    param()

    Write-DebugInfo "Attempting to get processor count..."
    try {
        # Get total logical cores from all processors
        $processorCount = (Get-WmiObject Win32_Processor -ErrorAction Stop).NumberOfCores | Measure-Object -Sum | Select-Object -ExpandProperty Sum
        Write-DebugInfo "Processor count (WMI): $processorCount"
        return $processorCount
    } catch {
        # Fallback to Environment.ProcessorCount if WMI fails (e.g., permissions, non-Windows)
        $fallbackCount = [Environment]::ProcessorCount
        Write-Log "Could not retrieve processor count via WMI. Falling back to Environment.ProcessorCount: $fallbackCount" -ForegroundColor $script:warningColor
        Write-DebugInfo "WMI error for processor count: $($_.Exception.Message)"
        return $fallbackCount
    }
}
