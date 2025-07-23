<#
.SYNOPSIS
Finds optimal HEVC encoding settings by analyzing content characteristics.

.DESCRIPTION
Automatically tests various encoding parameters and recommends the best 
balance between quality, file size, and encoding speed for specific video content.
Performs comprehensive analysis including quality metrics (VMAF, SSIM, PSNR),
bitrate distribution, and visual complexity scoring.

.PARAMETER InputPath
Path to the video file or folder containing videos to analyze.

.PARAMETER TestDuration
Duration (in seconds) of the test segment to use for optimization. Default: 60.

.PARAMETER QualityTarget
Target VMAF score for quality-constrained optimization (1-100). Default: 92.

.PARAMETER SpeedTarget
Target encoding speed (fps) for time-constrained optimization.

.PARAMETER ComplexityAnalysis
Perform detailed content complexity analysis.

.PARAMETER HardwareAcceleration
Use hardware acceleration if available (cuvid, qsv, vaapi).

.EXAMPLE
.\Optimize-HEVCSettings.ps1 -InputPath ".\4k_demo.mp4" -QualityTarget 95

.EXAMPLE
.\Optimize-HEVCSettings.ps1 -InputPath ".\videos\" -SpeedTarget 8 -ComplexityAnalysis -HardwareAcceleration
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
    [ValidateScript({Test-Path $_})]
    [string]$InputPath,
    
    [ValidateRange(10, 300)]
    [int]$TestDuration = 60,
    
    [ValidateRange(80, 99)]
    [int]$QualityTarget = 92,
    
    [ValidateRange(1, 120)]
    [int]$SpeedTarget,
    
    [switch]$ComplexityAnalysis,
    
    [switch]$HardwareAcceleration
)

begin {
    $VMAF_MODEL = "vmaf_v0.6.1.json"
    $MIN_FILE_SIZE = 10MB


    <#
    .SYNOPSIS
    Tests FFmpeg and FFprobe availability.
    
    .DESCRIPTION
    Verifies FFmpeg binaries are in PATH and checks for HEVC support.
    
    .OUTPUTS
    Boolean indicating if requirements are met.
    #>
    function Test-FFmpeg {
        try {
            $ffmpegVersion = ffmpeg -version 2>&1
            $ffprobeVersion = ffprobe -version 2>&1
            
            if ($LASTEXITCODE -ne 0) {
                return $false
            }
            
            # Check for libx265 encoder
            $encoders = ffmpeg -encoders 2>&1
            if ($encoders -notmatch "libx265") {
                Write-Host "HEVC encoder (libx265) not available in FFmpeg" -ForegroundColor Red
                return $false
            }
            
            return $true
        } 
        catch {
            return $false
        }
    }


    <#
    .SYNOPSIS
    Calculates video complexity score.
    
    .DESCRIPTION
    Analyzes visual complexity by measuring luminance variance in a thumbnail grid.
    Higher values indicate more complex/detailed content.
    
    .PARAMETER filePath
    Path to the video file.
    
    .OUTPUTS
    Complexity score (0-100 scale).
    #>
    function Get-VideoComplexity {
        param($filePath)
        
        $tempFile = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetTempFileName(), ".png")
        
        try {
            # Generate thumbnail grid
            $ffmpegArgs = @(
                "-i", "`"$filePath`"",
                "-vf", "select='not(mod(n,30))',scale=128:72,tile=10x10",
                "-frames:v", "1",
                "-y", "`"$tempFile`""
            )
            $null = ffmpeg $ffmpegArgs
            
            if (-not (Test-Path $tempFile)) {
                Write-Warning "Thumbnail generation failed"
                return 50  # Default average complexity
            }
            
            $histogram = [System.Drawing.Bitmap]::FromFile($tempFile)
            $varianceSum = 0
            $pixelCount = $histogram.Width * $histogram.Height
            
            for ($x = 0; $x -lt $histogram.Width; $x++) {
                for ($y = 0; $y -lt $histogram.Height; $y++) {
                    $pixel = $histogram.GetPixel($x, $y)
                    # Convert to luminance (perceptual)
                    $luma = (0.2126 * $pixel.R) + (0.7152 * $pixel.G) + (0.0722 * $pixel.B)
                    $varianceSum += [Math]::Pow($luma - 128, 2)
                }
            }
            
            # Normalize to 0-100 scale
            $complexity = [Math]::Min(100, [Math]::Sqrt($varianceSum / $pixelCount) * 0.5)
            return [Math]::Round($complexity, 1)
        } 
        catch {
            Write-Warning "Complexity analysis failed: $($_.Exception.Message)"
            return 50
        } 
        finally {
            if (Test-Path $tempFile) { Remove-Item $tempFile -ErrorAction SilentlyContinue }
        }
    }


    <#
    .SYNOPSIS
    Measures video quality metrics.
    
    .DESCRIPTION
    Calculates VMAF, PSNR, and SSIM scores between source and encoded videos.
    
    .PARAMETER original
    Path to source video file.
    
    .PARAMETER encoded
    Path to encoded video file.
    
    .OUTPUTS
    PSObject containing quality metrics.
    #>
    function Get-VideoQuality {
        param($original, $encoded)
        
        $logFile = New-TemporaryFile
        
        try {
            $ffmpegArgs = @(
                "-i", "`"$encoded`"",
                "-i", "`"$original`"",
                "-lavfi", "[0:v][1:v]libvmaf=log_path=$($logFile.FullName):model=path=`"$VMAF_MODEL`":psnr=1:ssim=1",
                "-f", "null", "-"
            )
            
            $null = ffmpeg $ffmpegArgs 2>$null
            
            $logContent = Get-Content $logFile
            $metrics = @{
                VMAF = 0
                PSNR = 0
                SSIM = 0
            }
            
            if ($logContent -match "VMAF score: (\d+\.\d+)") {
                $metrics.VMAF = [double]$Matches[1]
            }
            if ($logContent -match "PSNR score: (\d+\.\d+)") {
                $metrics.PSNR = [double]$Matches[1]
            }
            if ($logContent -match "SSIM score: (\d+\.\d+)") {
                $metrics.SSIM = [double]$Matches[1]
            }
            
            return $metrics
        } 
        catch {
            Write-Warning "Quality metrics failed: $($_.Exception.Message)"
            return @{
                VMAF = 0
                PSNR = 0
                SSIM = 0
            }
        } 
        finally {
            Remove-Item $logFile -ErrorAction SilentlyContinue
        }
    }


    <#
    .SYNOPSIS
    Tests encoding settings on a video segment.
    
    .DESCRIPTION
    Encodes a test segment with specified settings and measures performance metrics.
    
    .PARAMETER source
    Path to source video file.
    
    .PARAMETER settings
    Encoding settings (CRF, preset, etc.).
    
    .OUTPUTS
    PSObject containing test results.
    #>
    function Test-EncodingSettings {
        param($source, $settings)
        
        $outputFile = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetTempFileName(), ".mkv")
        
        try {
            # Base FFmpeg parameters
            $ffmpegArgs = @(
                "-hide_banner",
                "-y",
                "-i", "`"$source`"",
                "-t", $TestDuration
            )
            
            # Add hardware acceleration if requested and available
            if ($HardwareAcceleration) {
                $hwAccel = $null
                if (ffmpeg -hwaccels | Select-String "cuda") {
                    $hwAccel = "cuda"
                } elseif (ffmpeg -hwaccels | Select-String "dxva2") {
                    $hwAccel = "dxva2"
                }
                
                if ($hwAccel) {
                    $ffmpegArgs += "-hwaccel", $hwAccel
                    Write-Debug "Using hardware acceleration: $hwAccel"
                }
            }
            
            # Add encoding parameters
            $ffmpegArgs += @(
                "-c:v", "libx265",
                "-crf", $settings.CRF,
                "-preset", $settings.Preset,
                "-x265-params", "log-level=error:ssim=1:psnr=1",
                "-c:a", "copy",
                "`"$outputFile`""
            )
            
            # Execute encoding
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $process = Start-Process ffmpeg -ArgumentList $ffmpegArgs -NoNewWindow -PassThru -Wait
            $stopwatch.Stop()
            
            if ($process.ExitCode -ne 0) {
                throw "FFmpeg failed with exit code $($process.ExitCode)"
            }
            
            # Get quality metrics
            $quality = Get-VideoQuality $source $outputFile
            
            return [PSCustomObject]@{
                CRF = $settings.CRF
                Preset = $settings.Preset
                TimeSec = $stopwatch.Elapsed.TotalSeconds
                FileSizeMB = [Math]::Round((Get-Item $outputFile).Length / 1MB, 2)
                VMAF = $quality.VMAF
                PSNR = $quality.PSNR
                SSIM = $quality.SSIM
                SpeedFPS = $TestDuration / $stopwatch.Elapsed.TotalSeconds
            }
        } 
        catch {
            Write-Warning "Encoding test failed: $($_.Exception.Message)"
            return $null
        } 
        finally {
            if (Test-Path $outputFile) { Remove-Item $outputFile -ErrorAction SilentlyContinue }
        }
    }

    # Validate dependencies
    if (-not (Test-FFmpeg)) {
        Write-Host "FFmpeg/FFprobe not found or incompatible! Please install FFmpeg with HEVC support." -ForegroundColor Red
        exit 1
    }
}

process {
    # Collect files for processing
    $files = if (Test-Path $InputPath -PathType Container) {
        Get-ChildItem $InputPath -Include *.mp4, *.mkv, *.mov, *.avi -Recurse | 
        Where-Object Length -gt $MIN_FILE_SIZE
    } else {
        Get-Item $InputPath
    }

    if (-not $files) {
        Write-Host "No valid video files found!" -ForegroundColor Red
        exit 1
    }

    $results = [System.Collections.Generic.List[object]]::new()
    $recommendations = [System.Collections.Generic.List[object]]::new()

    foreach ($file in $files) {
        Write-Host "`n[$(Get-Date -Format 'HH:mm:ss')] Analyzing: $($file.Name)" -ForegroundColor Cyan
        Write-Host ("-" * 70)
        
        # Get video properties
        try {
            $ffprobeOutput = ffprobe -v error -select_streams v:0 `
                -show_entries stream=width,height,bit_rate,codec_name `
                -of json "$($file.FullName)" 2>$null
                
            $videoInfo = $ffprobeOutput | ConvertFrom-Json
        } 
        catch {
            Write-Host "Failed to get video info: $($_.Exception.Message)" -ForegroundColor Red
            continue
        }

        # Content complexity analysis
        $complexity = if ($ComplexityAnalysis) {
            Write-Host "Calculating content complexity..."
            Get-VideoComplexity $file.FullName
        } else { 
            Write-Host "Skipping complexity analysis"
            50 # Default value
        }
        
        Write-Host "Resolution: $($videoInfo.streams[0].width)x$($videoInfo.streams[0].height)"
        Write-Host "Bitrate: $([Math]::Round([int]$videoInfo.streams[0].bit_rate / 1Mb, 2)) Mbps"
        Write-Host "Complexity: $complexity/100"

        # Generate test clip
        $testClip = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetTempFileName(), $file.Extension)
        try {
            ffmpeg -hide_banner -y -i $file.FullName -ss 00:05:00 -t $TestDuration -c copy $testClip 2>$null
            if (-not (Test-Path $testClip)) {
                throw "Test clip creation failed"
            }
        } 
        catch {
            Write-Host "Error creating test clip: $($_.Exception.Message)" -ForegroundColor Red
            continue
        }

        # Define test configurations
        $testSettings = @()
        $res = [int]$videoInfo.streams[0].width
        
        # Dynamic CRF range based on resolution
        $crfRange = if ($res -ge 3840) { @(20, 22, 24, 26) } 
                    elseif ($res -ge 1920) { @(22, 24, 26) }
                    else { @(24, 26, 28) }
        
        # Dynamic presets based on complexity
        $presets = if ($complexity -gt 70) { @("medium", "slow") } else { @("fast", "medium") }

        # Generate test matrix
        foreach ($crf in $crfRange) {
            foreach ($preset in $presets) {
                $testSettings += [PSCustomObject]@{
                    CRF = $crf
                    Preset = $preset
                }
            }
        }

        # Run tests
        $fileResults = @()
        foreach ($setting in $testSettings) {
            Write-Host "Testing CRF $($setting.CRF) with $($setting.Preset) preset..."
            $result = Test-EncodingSettings $testClip $setting
            
            if ($result) {
                $fileResults += $result
                Write-Host ("• VMAF: {0} | PSNR: {1}dB | Size: {2}MB | Speed: {3}fps" -f 
                    [Math]::Round($result.VMAF, 2),
                    [Math]::Round($result.PSNR, 1),
                    $result.FileSizeMB,
                    [Math]::Round($result.SpeedFPS, 1))
            }
        }

        # Add to global results
        $results.AddRange($fileResults | Select-Object *, 
            @{Name="Source"; Expression={$file.Name}},
            @{Name="Complexity"; Expression={$complexity}})

        # Generate recommendations for this file
        $qualityRec = $fileResults | 
            Where-Object { $_.VMAF -ge $QualityTarget } |
            Sort-Object FileSizeMB |
            Select-Object -First 1

        $speedRec = if ($SpeedTarget) {
            $fileResults | 
                Where-Object { $_.SpeedFPS -ge $SpeedTarget } |
                Sort-Object VMAF -Descending |
                Select-Object -First 1
        }

        $balancedRec = $fileResults |
            Sort-Object { 
                [Math]::Abs($_.VMAF - $QualityTarget) * 0.7 + 
                ($_.FileSizeMB / 100) * 0.2 +
                ($_.TimeSec / 60) * 0.1
            } |
            Select-Object -First 1

        $recommendations.Add([PSCustomObject]@{
            File = $file.Name
            QualityRecommendation = if ($qualityRec) { "CRF $($qualityRec.CRF) $($qualityRec.Preset)" } else { "N/A" }
            SpeedRecommendation = if ($speedRec) { "CRF $($speedRec.CRF) $($speedRec.Preset)" } else { "N/A" }
            BalancedRecommendation = if ($balancedRec) { "CRF $($balancedRec.CRF) $($balancedRec.Preset)" } else { "N/A" }
            ExpectedQuality = if ($qualityRec) { [Math]::Round($qualityRec.VMAF) } else { 0 }
            ExpectedSizeReduction = if ($balancedRec) { [Math]::Round(100 - ($balancedRec.FileSizeMB / $fileResults[0].FileSizeMB * 100), 1) } else { 0 }
        })

        # Clean up
        Remove-Item $testClip -ErrorAction SilentlyContinue
        Write-Host ("-" * 70)
    }
}

end {
    # Generate report
    $reportDate = Get-Date -Format "yyyyMMdd-HHmmss"
    $csvPath = "HEVC_Optimization_$reportDate.csv"

    # Output results
    Write-Host "`n`n============= OPTIMIZATION RESULTS =============" -ForegroundColor Green
    $results | Export-Csv -Path $csvPath -NoTypeInformation

    Write-Host "`n==== RECOMMENDED SETTINGS ====" -ForegroundColor Cyan
    $recommendations | Format-Table -AutoSize

    Write-Host "`nDetailed recommendations:" -ForegroundColor Yellow
    foreach ($rec in $recommendations) {
        Write-Host ("`nFile: {0}" -f $rec.File) -ForegroundColor Magenta
        
        if ($rec.QualityRecommendation -ne "N/A") {
            Write-Host ("• Quality: {0} (Expected VMAF: {1})" -f $rec.QualityRecommendation, $rec.ExpectedQuality)
        }
        
        if ($SpeedTarget -and $rec.SpeedRecommendation -ne "N/A") {
            Write-Host ("• Speed: {0} (> {1} fps)" -f $rec.SpeedRecommendation, $SpeedTarget)
        }
        
        if ($rec.BalancedRecommendation -ne "N/A") {
            Write-Host ("• Balanced: {0} (Size reduction: {1}%)" -f $rec.BalancedRecommendation, $rec.ExpectedSizeReduction)
        }
    }

    Write-Host "`nFull results saved to: $csvPath" -ForegroundColor Green
    Write-Host "Optimization completed at $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor White
}