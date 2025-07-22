<#
.SYNOPSIS
Validates HEVC video conversions and verifies file integrity.

.DESCRIPTION
Performs comprehensive validation of HEVC video conversions to ensure quality and integrity.
This script performs multiple validation checks at different levels of depth based on the
verification mode selected.

Validation Checks:
- Basic codec verification (ensures proper HEVC encoding)
- Duration matching between source and converted files
- Frame count verification with tolerance
- Audio stream integrity validation
- Video stream quality assessment
- Basic playback validation
- Optional deep scanning with VMAF quality scoring

Verification Modes:
1. Basic: Quick validation of codec, duration, and basic playback
2. Full: Adds audio stream validation and more thorough checks
3. DeepScan: Comprehensive validation including VMAF scoring and video hash comparison

.PARAMETER SourcePath
Path to the directory containing original source video files.
The script will recursively search this directory for matching source files.

.PARAMETER ConvertedPath
Path to the directory containing HEVC converted video files.
Files should have '_x265' suffix in their names to be identified as conversions.

.PARAMETER VerificationMode
Sets the depth and thoroughness of the validation process.
Options:
- Basic: Quick validation (default)
- Full: Thorough validation including audio
- DeepScan: Complete validation including quality metrics

.PARAMETER GenerateReport
Switch parameter to enable CSV report generation.
The report includes detailed validation results for each file.

.PARAMETER VmafThreshold
Sets the minimum acceptable VMAF score for quality validation.
- Range: 80-100
- Default: 90
- Recommended: 95+ for high-quality conversions

.EXAMPLE
Verify-HEVCConversions -SourcePath ".\Originals" -ConvertedPath ".\Converted"
Performs basic validation of converted files.

.EXAMPLE
Verify-HEVCConversions -SourcePath "D:\Videos" -ConvertedPath "D:\HEVC" -VerificationMode Full -GenerateReport
Performs thorough validation and generates a CSV report.

.EXAMPLE
Verify-HEVCConversions -SourcePath "E:\Source" -ConvertedPath "E:\Encoded" -VerificationMode DeepScan -VmafThreshold 95
Performs comprehensive validation with strict quality requirements.

.NOTES
Author: Script Enhanced by AI Assistant
Version: 2.0
Requirements:
- PowerShell 5.1 or higher
- ffmpeg and ffprobe in system PATH
- VMAF model file (vmaf_v0.6.1.json) for quality scoring

.LINK
https://github.com/Netflix/vmaf
https://ffmpeg.org/
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, Position=0, HelpMessage="Path to directory containing source video files")]
    [ValidateScript({
        if (-not (Test-Path $_ -PathType Container)) {
            throw "Source path '$_' does not exist or is not a directory."
        }
        return $true
    })]
    [string]$SourcePath,
    
    [Parameter(Mandatory=$true, Position=1, HelpMessage="Path to directory containing converted HEVC files")]
    [ValidateScript({
        if (-not (Test-Path $_ -PathType Container)) {
            throw "Converted path '$_' does not exist or is not a directory."
        }
        return $true
    })]
    [string]$ConvertedPath,
    
    [Parameter(Position=2)]
    [ValidateSet("Basic", "Full", "DeepScan")]
    [string]$VerificationMode = "Basic",
    
    [Parameter(Position=3)]
    [switch]$GenerateReport,
    
    [Parameter(Position=4)]
    [ValidateRange(80,100)]
    [int]$VmafThreshold = 90
)

# Script initialization and environment checks
$ErrorActionPreference = 'Stop'
$VerbosePreference = $PSCmdlet.MyInvocation.BoundParameters["Verbose"] -eq $true

# Initialize script variables
$script:scriptStart = Get-Date
$script:vmafModel = "vmaf_v0.6.1.json"
$script:logFile = Join-Path $ConvertedPath "Validation_$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
$script:validationResults = [System.Collections.Generic.List[object]]::new()

# Initialize logging function
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] ${Level}: $Message"
    
    # Write to console with appropriate color
    switch ($Level) {
        'Info'    { Write-Verbose $logMessage }
        'Warning' { Write-Warning $Message }
        'Error'   { Write-Error $Message }
        'Success' { Write-Host $Message -ForegroundColor Green }
    }
    
    # Append to log file
    $logMessage | Out-File -FilePath $script:logFile -Append
}

# Verify required tools are available
function Test-Requirements {
    $tools = @('ffmpeg', 'ffprobe')
    $missingTools = @()
    
    foreach ($tool in $tools) {
        if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
            $missingTools += $tool
        }
    }
    
    if ($missingTools) {
        $errorMsg = "Missing required tools: $($missingTools -join ', ')"
        Write-Log $errorMsg -Level Error
        throw $errorMsg
    }
    
    # Verify VMAF model file if needed
    if ($VerificationMode -eq "DeepScan") {
        if (-not (Test-Path $vmafModel)) {
            $errorMsg = "VMAF model file not found: $vmafModel"
            Write-Log $errorMsg -Level Error
            throw $errorMsg
        }
    }
    
    Write-Log "Environment check passed - all required tools available" -Level Info
}

function Get-MediaHash {
    <#
    .SYNOPSIS
    Calculates hash value for a specific media stream.
    
    .DESCRIPTION
    Uses ffmpeg to compute SHA256 hash of video or audio streams.
    This function helps verify stream integrity and detect any modifications.
    
    .PARAMETER FilePath
    Full path to the media file to analyze.
    
    .PARAMETER StreamType
    Type of media stream to hash ("video" or "audio").
    Default is "video".
    
    .OUTPUTS
    Returns the SHA256 hash string or $null if calculation fails.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateScript({Test-Path $_ -PathType Leaf})]
        [string]$FilePath,
        
        [ValidateSet("video", "audio")]
        [string]$StreamType = "video"
    )
    
    Write-Log "Calculating $StreamType hash for: $FilePath" -Level Info
    
    $hash = $null
    try {
        $ffmpegArgs = @(
            "-i", "`"$FilePath`"",
            "-map", "0:$StreamType",
            "-c", "copy",
            "-f", "hash",
            "-hash", "sha256",
            "-"
        )
        
        $hashOutput = ffmpeg $ffmpegArgs 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "ffmpeg failed with exit code $LASTEXITCODE"
        }
        
        $hashLine = $hashOutput | Where-Object { $_ -match "SHA256=" }
        if ($hashLine) {
            $hash = $hashLine.Split('=')[1].Trim()
            Write-Log "Hash calculation successful" -Level Info
        } else {
            throw "No hash value found in output"
        }
    } catch {
        Write-Log "Hash calculation failed: $_" -Level Error
        return $null
    }
    return $hash
}

function Get-VideoProperties {
    <#
    .SYNOPSIS
    Retrieves detailed properties of a video file.
    
    .DESCRIPTION
    Uses ffprobe to extract video stream and format information including:
    - Codec name
    - Resolution (width/height)
    - Duration
    - Frame count
    - Format details
    
    .PARAMETER FilePath
    Full path to the video file to analyze.
    
    .OUTPUTS
    Returns a PSObject containing video properties or $null if analysis fails.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateScript({Test-Path $_ -PathType Leaf})]
        [string]$FilePath
    )
    
    Write-Log "Analyzing video properties for: $FilePath" -Level Info
    
    try {
        $ffprobeArgs = @(
            "-v", "error",
            "-select_streams", "v:0",
            "-show_entries", "stream=codec_name,width,height,duration,nb_frames",
            "-show_entries", "format=duration",
            "-of", "json",
            "`"$FilePath`""
        )
        
        $probeOutput = ffprobe $ffprobeArgs 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "ffprobe failed with exit code $LASTEXITCODE"
        }
        
        $properties = $probeOutput | ConvertFrom-Json
        if (-not $properties) {
            throw "Failed to parse ffprobe output"
        }
        
        Write-Log "Video properties retrieved successfully" -Level Info
        return $properties
        
    } catch {
        Write-Log "Failed to get video properties: $_" -Level Error
        return $null
    }
}

function Test-Vmaf {
    <#
    .SYNOPSIS
    Calculates VMAF quality score between source and converted videos.
    
    .DESCRIPTION
    Uses ffmpeg with libvmaf to compute video quality metrics.
    VMAF (Video Multi-Method Assessment Fusion) provides a
    perceptual video quality score from 0 to 100.
    
    .PARAMETER SourcePath
    Path to the original source video file.
    
    .PARAMETER ConvertedPath
    Path to the converted video file to compare.
    
    .OUTPUTS
    Returns the VMAF score (0-100) or $null if calculation fails.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateScript({Test-Path $_ -PathType Leaf})]
        [string]$SourcePath,
        
        [Parameter(Mandatory=$true)]
        [ValidateScript({Test-Path $_ -PathType Leaf})]
        [string]$ConvertedPath
    )
    
    Write-Log "Calculating VMAF score - Source: $SourcePath, Converted: $ConvertedPath" -Level Info
    
    $logFile = New-TemporaryFile
    try {
        $ffmpegArgs = @(
            "-i", "`"$ConvertedPath`"",
            "-i", "`"$SourcePath`"",
            "-lavfi", "[0:v][1:v]libvmaf=log_path=$($logFile.FullName):model=path=`"$vmafModel`"",
            "-f", "null", "-"
        )
        
        $output = ffmpeg $ffmpegArgs 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "ffmpeg failed with exit code $LASTEXITCODE`n$output"
        }
        
        $vmafResult = Get-Content $logFile -ErrorAction Stop | 
            Select-String "VMAF score: " | 
            ForEach-Object { [double]($_.Line.Split(':')[1].Trim()) }
        
        if ($null -eq $vmafResult) {
            throw "No VMAF score found in output"
        }
        
        Write-Log "VMAF calculation successful: $vmafResult" -Level Info
        return $vmafResult
        
    } catch {
        Write-Log "VMAF calculation failed: $_" -Level Error
        return $null
    } finally {
        Remove-Item $logFile -ErrorAction SilentlyContinue
    }
}

function Test-Playback {
    <#
    .SYNOPSIS
    Performs basic playback validation of a video file.
    
    .DESCRIPTION
    Attempts to decode a short segment of the video to verify
    basic playback functionality and file integrity.
    
    .PARAMETER FilePath
    Full path to the video file to test.
    
    .PARAMETER Duration
    Number of seconds to test (default: 10).
    
    .OUTPUTS
    Returns $true if playback test passes, $false otherwise.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateScript({Test-Path $_ -PathType Leaf})]
        [string]$FilePath,
        
        [Parameter()]
        [int]$Duration = 10
    )
    
    Write-Log "Testing playback for: $FilePath" -Level Info
    
    try {
        $ffmpegArgs = @(
            "-i", "`"$FilePath`"",
            "-t", "$Duration",
            "-f", "null", "-"
        )
        
        $output = ffmpeg $ffmpegArgs 2>&1
        $success = $LASTEXITCODE -eq 0
        
        if ($success) {
            Write-Log "Playback test passed" -Level Info
        } else {
            Write-Log "Playback test failed: Exit code $LASTEXITCODE" -Level Warning
        }
        
        return $success
        
    } catch {
        Write-Log "Playback test failed with error: $_" -Level Error
        return $false
    }
}
}

# Main validation process
try {
    # Verify environment and requirements
    Test-Requirements
    
    Write-Log "Starting validation process - Mode: $VerificationMode" -Level Info
    Write-Log "Source path: $SourcePath" -Level Info
    Write-Log "Converted path: $ConvertedPath" -Level Info
    
    # Find converted files
    $convertedFiles = Get-ChildItem -Path $ConvertedPath -Recurse -Include "*.mkv", "*.mp4" |
        Where-Object { $_.Name -match "_x265" }
    
    if (-not $convertedFiles) {
        $errorMsg = "No converted files found in $ConvertedPath"
        Write-Log $errorMsg -Level Error
        throw $errorMsg
    }
    
    Write-Log "Found $($convertedFiles.Count) converted files to validate" -Level Info

    # Process each file
    $processedCount = 0
    foreach ($convertedFile in $convertedFiles) {
        $processedCount++
        $progress = [Math]::Round(($processedCount / $convertedFiles.Count) * 100, 1)
        
        Write-Progress -Activity "Validating HEVC Conversions" `
            -Status "Processing $($convertedFile.Name) ($processedCount of $($convertedFiles.Count))" `
            -PercentComplete $progress
        
        $result = [PSCustomObject]@{
            FileName = $convertedFile.Name
            FilePath = $convertedFile.FullName
            SourceFound = $false
            ValidationPassed = $false
            CodecValid = $false
            DurationMatch = $false
            FrameMatch = $false
            AudioHashMatch = $false
            VideoHashMatch = $false
            PlaybackOK = $false
            VMAFScore = 0
            ValidationTime = 0
            Status = "Pending"
            Errors = [System.Collections.Generic.List[string]]::new()
        }
        
        $validationStart = Get-Date
        Write-Log "Starting validation for: $($convertedFile.Name)" -Level Info
        
        try {
            # Find matching source file
            $sourceName = $convertedFile.Name -replace '_x265\.(mkv|mp4)$', '.$1'
            $sourceFile = Get-ChildItem -Path $SourcePath -Recurse -Filter $sourceName | Select-Object -First 1
            
            if (-not $sourceFile) {
                throw "Source file not found: $sourceName"
            }
            
            $result.SourceFound = $true
            Write-Log "Found matching source file: $($sourceFile.Name)" -Level Info
            
            # Get media properties
            Write-Log "Analyzing media properties" -Level Info
            $sourceProps = Get-VideoProperties $sourceFile.FullName
            $convertedProps = Get-VideoProperties $convertedFile.FullName
            
            if (-not $sourceProps -or -not $convertedProps) {
                throw "Failed to read media properties"
            }
            
            # Codec validation
            $result.CodecValid = $convertedProps.streams[0].codec_name -eq "hevc"
            if (-not $result.CodecValid) {
                $result.Errors.Add("Invalid codec: $($convertedProps.streams[0].codec_name)")
                Write-Log "Invalid codec detected: $($convertedProps.streams[0].codec_name)" -Level Warning
            }
            
            # Duration validation (allow 0.5% variance)
            $sourceDuration = [double]$sourceProps.format.duration
            $convertedDuration = [double]$convertedProps.format.duration
            $durationDiff = [Math]::Abs($sourceDuration - $convertedDuration)
            $durationThreshold = $sourceDuration * 0.005
            
            $result.DurationMatch = $durationDiff -le $durationThreshold
            if (-not $result.DurationMatch) {
                $result.Errors.Add("Duration mismatch: Source $([Math]::Round($sourceDuration,3))s vs Converted $([Math]::Round($convertedDuration,3))s")
                Write-Log "Duration mismatch detected" -Level Warning
            }
            
            # Frame count validation (allow 1% variance)
            if ($sourceProps.streams[0].nb_frames -and $convertedProps.streams[0].nb_frames) {
                $sourceFrames = [int]$sourceProps.streams[0].nb_frames
                $convertedFrames = [int]$convertedProps.streams[0].nb_frames
                $frameDiff = [Math]::Abs($sourceFrames - $convertedFrames)
                $frameThreshold = $sourceFrames * 0.01
                
                $result.FrameMatch = $frameDiff -le $frameThreshold
                if (-not $result.FrameMatch) {
                    $result.Errors.Add("Frame count mismatch: Source $sourceFrames vs Converted $convertedFrames")
                    Write-Log "Frame count mismatch detected" -Level Warning
                }
            }
            
            # Audio hash comparison for Full and DeepScan modes
            if ($VerificationMode -in @("Full", "DeepScan")) {
                Write-Log "Performing audio stream validation" -Level Info
                $sourceAudioHash = Get-MediaHash $sourceFile.FullName "audio"
                $convertedAudioHash = Get-MediaHash $convertedFile.FullName "audio"
                
                $result.AudioHashMatch = $sourceAudioHash -eq $convertedAudioHash
                if (-not $result.AudioHashMatch) {
                    $result.Errors.Add("Audio stream integrity check failed")
                    Write-Log "Audio stream hash mismatch detected" -Level Warning
                }
            }
            
            # Video hash comparison for DeepScan mode
            if ($VerificationMode -eq "DeepScan") {
                Write-Log "Performing deep video analysis" -Level Info
                $sourceVideoHash = Get-MediaHash $sourceFile.FullName "video"
                $convertedVideoHash = Get-MediaHash $convertedFile.FullName "video"
                
                $result.VideoHashMatch = $sourceVideoHash -eq $convertedVideoHash
                if (-not $result.VideoHashMatch) {
                    $result.Errors.Add("Video stream integrity check failed")
                    Write-Log "Video stream hash mismatch detected" -Level Warning
                }
            }
            
            # Basic playback test
            Write-Log "Performing playback test" -Level Info
            $result.PlaybackOK = Test-Playback $convertedFile.FullName
            if (-not $result.PlaybackOK) {
                $result.Errors.Add("Playback test failed")
            }
            
            # VMAF quality scoring for DeepScan mode
            if ($VerificationMode -eq "DeepScan") {
                Write-Log "Calculating VMAF quality score" -Level Info
                $result.VMAFScore = Test-Vmaf $sourceFile.FullName $convertedFile.FullName
                if ($result.VMAFScore -lt $VmafThreshold) {
                    $result.Errors.Add("VMAF score below threshold: $($result.VMAFScore) < $VmafThreshold")
                    Write-Log "Low VMAF score detected: $($result.VMAFScore)" -Level Warning
                }
            }
            
            # Determine overall validation status
            $result.ValidationPassed = $result.CodecValid -and
                $result.DurationMatch -and
                $result.PlaybackOK -and
                ($result.VMAFScore -ge $VmafThreshold -or $VerificationMode -ne "DeepScan") -and
                ($VerificationMode -ne "DeepScan" -or $result.VideoHashMatch)
            
            $result.Status = if ($result.ValidationPassed) { "Success" } else { "Failed" }
            
            # Log validation result
            $statusLevel = if ($result.ValidationPassed) { "Success" } else { "Warning" }
            Write-Log "Validation $($result.Status) for $($convertedFile.Name)" -Level $statusLevel
            
        } catch {
            $result.Status = "Error"
            $result.Errors.Add("Validation error: $($_.Exception.Message)")
            Write-Log "Validation error for $($convertedFile.Name): $_" -Level Error
        } finally {
            $result.ValidationTime = [Math]::Round(((Get-Date) - $validationStart).TotalSeconds, 2)
            $null = $validationResults.Add($result)
        }
    }
    
    Write-Progress -Activity "Validating HEVC Conversions" -Completed

    # Generate report if requested
    if ($GenerateReport) {
        try {
            Write-Log "Generating validation report" -Level Info
            $reportPath = Join-Path $ConvertedPath "ValidationReport_$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
            
            $validationResults | 
                Select-Object FileName, Status, ValidationPassed, CodecValid,
                    DurationMatch, FrameMatch, AudioHashMatch, VideoHashMatch, 
                    PlaybackOK, VMAFScore, ValidationTime, 
                    @{Name="Errors";Expression={$_.Errors -join "; "}} | 
                Export-Csv -Path $reportPath -NoTypeInformation -Encoding utf8
            
            Write-Log "Report saved to: $reportPath" -Level Success
            Write-Host "Validation report saved to: $reportPath" -ForegroundColor Cyan
        } catch {
            Write-Log "Failed to generate report: $_" -Level Error
            Write-Warning "Failed to generate report: $_"
        }
    }
    
    # Output summary
    $totalTime = [Math]::Round(((Get-Date) - $scriptStart).TotalMinutes, 2)
    $passedCount = ($validationResults | Where-Object ValidationPassed).Count
    $failedCount = $validationResults.Count - $passedCount
    
    Write-Host "`nValidation Summary" -ForegroundColor Cyan
    Write-Host "----------------------------------------" -ForegroundColor Cyan
    Write-Host "Files processed: " -NoNewline
    Write-Host $validationResults.Count -ForegroundColor White
    Write-Host "Validation passed: " -NoNewline
    Write-Host $passedCount -ForegroundColor Green
    Write-Host "Validation failed: " -NoNewline
    Write-Host $failedCount -ForegroundColor $(if ($failedCount -gt 0) { 'Red' } else { 'Green' })
    Write-Host "Total validation time: " -NoNewline
    Write-Host "${totalTime} minutes" -ForegroundColor White
    Write-Host "Verification mode: " -NoNewline
    Write-Host $VerificationMode -ForegroundColor Cyan
    
    if ($failedCount -gt 0) {
        Write-Host "`nFailed files:" -ForegroundColor Red
        $validationResults | Where-Object { -not $_.ValidationPassed } | ForEach-Object {
            Write-Host " - $($_.FileName)" -ForegroundColor Red
            $_.Errors | ForEach-Object {
                Write-Host "   → $_" -ForegroundColor Yellow
            }
        }
    }
    
    Write-Log "Validation process completed - Passed: $passedCount, Failed: $failedCount" -Level Info
    
} catch {
    Write-Log "Validation process failed: $_" -Level Error
    Write-Error $_
    exit 1
}