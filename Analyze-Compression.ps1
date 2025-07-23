<#
.SYNOPSIS
Analyzes compression efficiency and quality metrics for HEVC video conversions.

.DESCRIPTION
Performs comprehensive analysis of HEVC video compression results by comparing source and converted files.
Generates detailed metrics and reports to evaluate compression efficiency and quality preservation.

Key Features:
- Compression ratio and space savings analysis
- Bitrate analysis and efficiency metrics
- Visual quality assessment (PSNR, SSIM, VMAF)
- Quality-per-bit efficiency scoring
- Multi-format reporting (Console, HTML, CSV)
- Visual data representation through charts
- Batch processing with detailed logging

.PARAMETER SourcePath
Path to the directory containing original source video files.
The script will recursively search this directory for matching source files.

.PARAMETER ConvertedPath
Path to the directory containing HEVC converted video files.
Files should have '_x265' suffix in their names to be identified as conversions.

.PARAMETER OutputFormat
Specifies the format(s) for the analysis report output.
Valid options:
- Console: Displays results in the PowerShell console
- HTML: Generates a detailed HTML report with styling
- CSV: Exports raw data in CSV format
- All: Generates all available report formats
Default value: "Console"

.PARAMETER GenerateCharts
Switch parameter to enable generation of visual charts and graphs.
Requires Python with matplotlib installed.
Charts include:
- Compression efficiency vs quality scatter plot
- Bitrate vs quality analysis
- Quality score distribution
- Compression ratio distribution

.EXAMPLE
Analyze-Compression -SourcePath ".\Originals" -ConvertedPath ".\Converted"
Performs basic analysis with console output only.

.EXAMPLE
Analyze-Compression -SourcePath "D:\Videos" -ConvertedPath "D:\HEVC" -OutputFormat HTML -GenerateCharts
Performs full analysis with HTML report and visual charts.

.EXAMPLE
Analyze-Compression -SourcePath "E:\Source" -ConvertedPath "E:\Encoded" -OutputFormat All
Generates comprehensive reports in all available formats.

.NOTES
Author: Script Enhanced by AI Assistant
Version: 2.0
Requirements:
- PowerShell 5.1 or higher
- ffmpeg and ffprobe in system PATH
- Python with matplotlib (only for chart generation)
- VMAF model file (vmaf_v0.6.1.json)

.LINK
https://github.com/Netflix/vmaf
https://ffmpeg.org/
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, Position=0, HelpMessage="Path to directory containing source video files")]
    [ValidateScript({Test-Path $_ -PathType Container})]
    [string]$SourcePath,
    
    [Parameter(Mandatory=$true, Position=1, HelpMessage="Path to directory containing converted HEVC files")]
    [ValidateScript({Test-Path $_ -PathType Container})]
    [string]$ConvertedPath,
    
    [Parameter(Position=2)]
    [ValidateSet("Console", "HTML", "CSV", "All")]
    [string]$OutputFormat = "Console",
    
    [Parameter(Position=3)]
    [switch]$GenerateCharts
)

# Script initialization and environment checks
$ErrorActionPreference = 'Stop'
$VerbosePreference = $PSCmdlet.MyInvocation.BoundParameters["Verbose"] -eq $true

# Initialize script variables
$script:scriptStart = Get-Date
$script:results = [System.Collections.Generic.List[object]]::new()
$script:vmafModel = "vmaf_v0.6.1.json"
$script:logFile = Join-Path $ConvertedPath "Analysis_$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

# Initialize logging function
function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [ValidateSet('Info', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] ${Level}: $Message"
    
    # Write to console with appropriate color
    switch ($Level) {
        'Info'    { Write-Verbose $logMessage }
        'Warning' { Write-Warning $Message }
        'Error'   { Write-Error $Message }
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
    
    if ($GenerateCharts) {
        try {
            $null = python -c "import matplotlib" 2>$null
        } catch {
            $missingTools += "Python with matplotlib"
        }
    }
    
    if ($missingTools) {
        $errorMsg = "Missing required tools: $($missingTools -join ', ')"
        Write-Log $errorMsg -Level Error
        throw $errorMsg
    }
    
    # Verify VMAF model file
    if (-not (Test-Path $vmafModel)) {
        $errorMsg = "VMAF model file not found: $vmafModel"
        Write-Log $errorMsg -Level Error
        throw $errorMsg
    }
    
    Write-Log "Environment check passed - all required tools available" -Level Info
}

function Get-MediaMetrics {
    <#
    .SYNOPSIS
    Retrieves basic media file metrics using ffprobe.
    
    .DESCRIPTION
    Extracts file size, duration, and calculates bitrate for a given media file.
    Uses ffprobe to obtain accurate duration information.
    
    .PARAMETER FilePath
    Full path to the media file to analyze.
    
    .OUTPUTS
    Returns a hashtable containing Size, Duration, and Bitrate values.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateScript({Test-Path $_ -PathType Leaf})]
        [string]$FilePath
    )
    
    Write-Log "Analyzing media metrics for: $FilePath" -Level Info
    
    $metrics = @{
        Size = 0
        Duration = 0
        Bitrate = 0
    }
    
    try {
        $file = Get-Item $FilePath
        $metrics.Size = $file.Length
        
        # Get duration using ffprobe
        $ffprobeArgs = @(
            "-v", "error",
            "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1",
            "`"$FilePath`""
        )
        
        $duration = ffprobe $ffprobeArgs 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "ffprobe failed with exit code $LASTEXITCODE"
        }
        
        if (-not [double]::TryParse($duration, [ref]$metrics.Duration)) {
            throw "Invalid duration value: $duration"
        }
        
        # Calculate bitrate (bits per second)
        if ($metrics.Duration -gt 0) {
            $metrics.Bitrate = ($metrics.Size * 8) / $metrics.Duration
            Write-Log "Media metrics obtained successfully - Size: $([Math]::Round($metrics.Size/1MB, 2))MB, Duration: $([Math]::Round($metrics.Duration, 2))s" -Level Info
        } else {
            throw "Invalid duration: 0 seconds"
        }
        
    } catch {
        $errorMsg = "Error getting metrics for $FilePath : $_"
        Write-Log $errorMsg -Level Error
        throw $errorMsg
    }
    
    return $metrics
}

function Get-QualityMetrics {
    <#
    .SYNOPSIS
    Calculates video quality metrics between source and converted files.
    
    .DESCRIPTION
    Uses ffmpeg with libvmaf to compute PSNR, SSIM, and VMAF quality metrics
    between a source video and its converted version.
    
    .PARAMETER SourcePath
    Path to the original source video file.
    
    .PARAMETER ConvertedPath
    Path to the converted video file to compare against the source.
    
    .OUTPUTS
    Returns a hashtable containing PSNR, SSIM, and VMAF scores.
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
    
    Write-Log "Calculating quality metrics - Source: $SourcePath, Converted: $ConvertedPath" -Level Info
    
    $metrics = @{
        PSNR = $null
        SSIM = $null
        VMAF = $null
    }
    
    $logFile = New-TemporaryFile
    
    try {
        $ffmpegArgs = @(
            "-i", "`"$ConvertedPath`"",
            "-i", "`"$SourcePath`"",
            "-filter_complex", 
            "[0:v][1:v]libvmaf=model=path=`"$vmafModel`":psnr=1:ssim=1:log_path=$($logFile.FullName)",
            "-f", "null", "-"
        )
        
        $output = ffmpeg $ffmpegArgs 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "ffmpeg failed with exit code $LASTEXITCODE`n$output"
        }
        
        # Parse log file with error handling
        $logContent = Get-Content $logFile -ErrorAction Stop
        
        # Extract metrics with validation
        $psnrMatch = $logContent | Select-String "psnr_avg:(\d+\.\d+)"
        $ssimMatch = $logContent | Select-String "ssim_avg:(\d+\.\d+)"
        $vmafMatch = $logContent | Select-String "VMAF score: (\d+\.\d+)"
        
        if ($psnrMatch) { $metrics.PSNR = [double]$psnrMatch.Matches.Groups[1].Value }
        if ($ssimMatch) { $metrics.SSIM = [double]$ssimMatch.Matches.Groups[1].Value }
        if ($vmafMatch) { $metrics.VMAF = [double]$vmafMatch.Matches.Groups[1].Value }
        
        if ($null -eq $metrics.VMAF) {
            throw "Failed to extract quality metrics from log file"
        }
        
        Write-Log "Quality metrics calculated successfully - VMAF: $($metrics.VMAF), PSNR: $($metrics.PSNR), SSIM: $($metrics.SSIM)" -Level Info
        
    } catch {
        $errorMsg = "Quality metrics calculation failed: $_"
        Write-Log $errorMsg -Level Error
        throw $errorMsg
    } finally {
        Remove-Item $logFile -ErrorAction SilentlyContinue
    }
    
    return $metrics
}

# Main analysis process
try {
    # Verify environment and requirements
    Test-Requirements
    
    Write-Log "Starting compression analysis - Source: $SourcePath, Converted: $ConvertedPath" -Level Info
    
    # Find converted files
    $convertedFiles = Get-ChildItem -Path $ConvertedPath -Recurse -Include "*.mkv", "*.mp4" |
        Where-Object { $_.Name -match "_x265" }
    
    if (-not $convertedFiles) {
        $errorMsg = "No converted files found in $ConvertedPath"
        Write-Log $errorMsg -Level Error
        throw $errorMsg
    }
    
    Write-Log "Found $($convertedFiles.Count) converted files to analyze" -Level Info
    
    # Process each file
    $processedCount = 0
    foreach ($convertedFile in $convertedFiles) {
        $processedCount++
        $progress = [Math]::Round(($processedCount / $convertedFiles.Count) * 100, 1)
        
        Write-Progress -Activity "Analyzing HEVC Conversions" `
            -Status "Processing $($convertedFile.Name) ($processedCount of $($convertedFiles.Count))" `
            -PercentComplete $progress
        
        $analysisStart = Get-Date
        $result = [PSCustomObject]@{
            FileName = $convertedFile.Name
            SourceSize = 0
            ConvertedSize = 0
            SizeReduction = 0
            CompressionRatio = 0
            SourceBitrate = 0
            ConvertedBitrate = 0
            BitrateReduction = 0
            PSNR = 0
            SSIM = 0
            VMAF = 0
            QPScore = 0  # Quality-per-bit score
            AnalysisTime = 0
            Status = "Success"
            ErrorDetails = $null
        }
        
        try {
            Write-Log "Processing file: $($convertedFile.Name)" -Level Info
            
            # Find matching source file
            $sourceName = $convertedFile.Name -replace '_x265\.(mkv|mp4)$', '.$1'
            $sourceFile = Get-ChildItem -Path $SourcePath -Recurse -Filter $sourceName | Select-Object -First 1
            
            if (-not $sourceFile) {
                throw "Source file not found: $sourceName"
            }
            
            # Get basic metrics
            $sourceMetrics = Get-MediaMetrics $sourceFile.FullName
            $convertedMetrics = Get-MediaMetrics $convertedFile.FullName
            
            # Calculate size and bitrate metrics
            $result.SourceSize = $sourceMetrics.Size
            $result.ConvertedSize = $convertedMetrics.Size
            $result.SizeReduction = [Math]::Round(($sourceMetrics.Size - $convertedMetrics.Size) / $sourceMetrics.Size * 100, 2)
            $result.CompressionRatio = [Math]::Round($sourceMetrics.Size / $convertedMetrics.Size, 2)
            $result.SourceBitrate = [Math]::Round($sourceMetrics.Bitrate / 1000, 2)  # kbps
            $result.ConvertedBitrate = [Math]::Round($convertedMetrics.Bitrate / 1000, 2)  # kbps
            $result.BitrateReduction = [Math]::Round(($result.SourceBitrate - $result.ConvertedBitrate) / $result.SourceBitrate * 100, 2)
            
            # Get quality metrics
            $qualityMetrics = Get-QualityMetrics $sourceFile.FullName $convertedFile.FullName
            $result.PSNR = $qualityMetrics.PSNR
            $result.SSIM = $qualityMetrics.SSIM
            $result.VMAF = $qualityMetrics.VMAF
            
            # Calculate quality-per-bit score
            if ($result.ConvertedBitrate -gt 0) {
                $result.QPScore = [Math]::Round(($result.VMAF * 10) / $result.ConvertedBitrate, 4)
            }
            
            Write-Log "Analysis completed for $($convertedFile.Name) - VMAF: $($result.VMAF), Compression: $($result.SizeReduction)%" -Level Info
            
        } catch {
            $result.Status = "Failed"
            $result.ErrorDetails = $_.Exception.Message
            Write-Log "Analysis failed for $($convertedFile.Name): $_" -Level Error
        } finally {
            $result.AnalysisTime = [Math]::Round(((Get-Date) - $analysisStart).TotalSeconds, 2)
            $null = $results.Add($result)
        }
    }
    
    Write-Progress -Activity "Analyzing HEVC Conversions" -Completed
    
    # Generate reports
    Write-Log "Generating analysis reports" -Level Info
if ($OutputFormat -in @("HTML", "All")) {
    try {
        Write-Log "Generating HTML report" -Level Info
        
        $successCount = ($results | Where-Object Status -eq "Success").Count
        $failureCount = ($results | Where-Object Status -eq "Failed").Count
        $avgVmaf = [Math]::Round(($results | Where-Object Status -eq "Success" | Measure-Object -Property VMAF -Average).Average, 2)
        $avgCompression = [Math]::Round(($results | Where-Object Status -eq "Success" | Measure-Object -Property SizeReduction -Average).Average, 2)
        
        $htmlReport = @"
<!DOCTYPE html>
<html>
<head>
    <title>HEVC Compression Analysis Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; color: #333; }
        .container { max-width: 1200px; margin: 0 auto; }
        table { border-collapse: collapse; width: 100%; margin-bottom: 20px; box-shadow: 0 1px 3px rgba(0,0,0,0.2); }
        th, td { border: 1px solid #ddd; padding: 12px; text-align: right; }
        th { background-color: #2c3e50; color: white; text-align: center; }
        tr:nth-child(even) { background-color: #f8f9fa; }
        tr:hover { background-color: #f1f1f1; }
        .summary { background-color: #ecf0f1; padding: 20px; border-radius: 8px; margin-bottom: 30px; }
        .header { background-color: #34495e; color: white; padding: 20px; border-radius: 8px; margin-bottom: 20px; }
        .stats { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; margin-bottom: 20px; }
        .stat-card { background-color: white; padding: 15px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .success { color: #27ae60; }
        .warning { color: #e67e22; }
        .error { color: #c0392b; }
        .stat-value { font-size: 24px; font-weight: bold; margin: 10px 0; }
        .stat-label { color: #7f8c8d; font-size: 14px; }
        .error-row { background-color: #ffebee; color: #c0392b; font-size: 0.9em; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>HEVC Compression Analysis Report</h1>
            <p>Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
            <p>Source Path: $SourcePath</p>
            <p>Converted Path: $ConvertedPath</p>
        </div>
        
        <div class="summary">
            <h2>Analysis Summary</h2>
            <div class="stats">
                <div class="stat-card">
                    <div class="stat-label">Total Files</div>
                    <div class="stat-value">$($results.Count)</div>
                </div>
                <div class="stat-card">
                    <div class="stat-label">Successful Analyses</div>
                    <div class="stat-value success">$successCount</div>
                </div>
                <div class="stat-card">
                    <div class="stat-label">Failed Analyses</div>
                    <div class="stat-value $(if ($failureCount -gt 0) { 'error' } else { 'success' })">$failureCount</div>
                </div>
                <div class="stat-card">
                    <div class="stat-label">Average VMAF Score</div>
                    <div class="stat-value $(if ($avgVmaf -ge 95) { 'success' } elseif ($avgVmaf -ge 90) { 'warning' } else { 'error' })">$avgVmaf</div>
                </div>
                <div class="stat-card">
                    <div class="stat-label">Average Size Reduction</div>
                    <div class="stat-value">$avgCompression%</div>
                </div>
            </div>
        </div>
        
        <h2>Detailed Analysis Results</h2>
        <table>
            <tr>
                <th>File Name</th>
                <th>Status</th>
                <th>Size Reduction (%)</th>
                <th>Compression Ratio</th>
                <th>VMAF</th>
                <th>PSNR</th>
                <th>SSIM</th>
                <th>QP Score</th>
                <th>Analysis Time (s)</th>
            </tr>
"@

        foreach ($result in $results) {
            $statusClass = if ($result.Status -eq "Success") { "success" } else { "error" }
            $vmafClass = if ($result.VMAF -ge 95) { "success" } elseif ($result.VMAF -ge 90) { "warning" } else { "error" }
            
            $htmlReport += @"
            <tr>
                <td style="text-align: left">$($result.FileName)</td>
                <td class="$statusClass">$($result.Status)</td>
                <td>$($result.SizeReduction)</td>
                <td>$($result.CompressionRatio):1</td>
                <td class="$vmafClass">$($result.VMAF)</td>
                <td>$($result.PSNR)</td>
                <td>$($result.SSIM)</td>
                <td>$($result.QPScore)</td>
                <td>$($result.AnalysisTime)</td>
            </tr>
"@
            if ($result.Status -eq "Failed") {
                $htmlReport += @"
            <tr>
                <td colspan="9" class="error-row" style="text-align: left">
                    Error: $($result.ErrorDetails)
                </td>
            </tr>
"@
            }
        }

        $htmlReport += @"
        </table>
    </div>
</body>
</html>
"@

        $htmlPath = Join-Path $ConvertedPath "CompressionAnalysis_$(Get-Date -Format 'yyyyMMdd-HHmmss').html"
        $htmlReport | Out-File -FilePath $htmlPath -Encoding utf8
        Write-Log "HTML report saved to: $htmlPath" -Level Info
        Write-Host "HTML report saved to: $htmlPath" -ForegroundColor Cyan
        
    } catch {
        Write-Log "Failed to generate HTML report: $_" -Level Error
        Write-Warning "Failed to generate HTML report: $_"
    }
}

if ($OutputFormat -in @("CSV", "All")) {
    try {
        Write-Log "Generating CSV report" -Level Info
        $csvPath = Join-Path $ConvertedPath "CompressionAnalysis_$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
        $results | Export-Csv -Path $csvPath -NoTypeInformation -Encoding utf8
        Write-Log "CSV report saved to: $csvPath" -Level Info
        Write-Host "CSV report saved to: $csvPath" -ForegroundColor Cyan
    } catch {
        Write-Log "Failed to generate CSV report: $_" -Level Error
        Write-Warning "Failed to generate CSV report: $_"
    }
}

# Console output
if ($OutputFormat -in @("Console", "All")) {
    try {
        Write-Log "Generating console report" -Level Info
        
        Write-Host "`nCompression Analysis Summary" -ForegroundColor Cyan
        Write-Host "----------------------------------------" -ForegroundColor Cyan
        Write-Host "Total files analyzed: " -NoNewline
        Write-Host $results.Count -ForegroundColor White
        Write-Host "Successful analyses: " -NoNewline
        Write-Host ($results | Where-Object Status -eq "Success").Count -ForegroundColor Green
        Write-Host "Failed analyses: " -NoNewline
        $failedCount = ($results | Where-Object Status -eq "Failed").Count
        Write-Host $failedCount -ForegroundColor $(if ($failedCount -gt 0) { 'Red' } else { 'Green' })
        
        $successfulResults = $results | Where-Object Status -eq "Success"
        if ($successfulResults) {
            Write-Host "`nQuality Metrics (successful conversions only):" -ForegroundColor Cyan
            Write-Host "Average VMAF score: " -NoNewline
            $avgVmaf = [Math]::Round(($successfulResults | Measure-Object -Property VMAF -Average).Average, 2)
            Write-Host $avgVmaf -ForegroundColor $(if ($avgVmaf -ge 95) { 'Green' } elseif ($avgVmaf -ge 90) { 'Yellow' } else { 'Red' })
            
            Write-Host "Average size reduction: " -NoNewline
            Write-Host "$([Math]::Round(($successfulResults | Measure-Object -Property SizeReduction -Average).Average, 2))%" -ForegroundColor White
            
            Write-Host "Average bitrate reduction: " -NoNewline
            Write-Host "$([Math]::Round(($successfulResults | Measure-Object -Property BitrateReduction -Average).Average, 2))%" -ForegroundColor White
            
            Write-Host "Average quality-per-bit score: " -NoNewline
            Write-Host "$([Math]::Round(($successfulResults | Measure-Object -Property QPScore -Average).Average, 4))" -ForegroundColor White
            
            Write-Host "`nTop 5 files by compression efficiency:" -ForegroundColor Cyan
            $successfulResults | 
                Sort-Object QPScore -Descending | 
                Select-Object -First 5 | 
                Format-Table @(
                    @{Name="File Name"; Expression={$_.FileName}},
                    @{Name="Size Red(%)"; Expression={$_.SizeReduction}; Format="{0:N1}"},
                    @{Name="VMAF"; Expression={$_.VMAF}; Format="{0:N1}"},
                    @{Name="QP Score"; Expression={$_.QPScore}; Format="{0:N3}"}
                ) -AutoSize
        }
        
        if ($failedCount -gt 0) {
            Write-Host "`nFailed Analyses:" -ForegroundColor Red
            $results | Where-Object Status -eq "Failed" | ForEach-Object {
                Write-Host "  - $($_.FileName)" -ForegroundColor Red
                Write-Host "    Error: $($_.ErrorDetails)" -ForegroundColor Yellow
            }
        }
        
    } catch {
        Write-Log "Failed to generate console report: $_" -Level Error
        Write-Warning "Failed to generate console report: $_"
    }
}
}

# Generate charts
if ($GenerateCharts) {
    try {
        Write-Log "Generating visualization charts" -Level Info
        Write-Host "`nGenerating visualization charts..." -ForegroundColor Cyan
        
        # Save data for Python processing
        $jsonData = $results | ConvertTo-Json -Depth 3
        $dataPath = Join-Path $ConvertedPath "chart_data.json"
        $jsonData | Out-File -FilePath $dataPath -Encoding utf8
        
        # Enhanced Python chart generation script with error handling and better styling
        $pythonScript = @"
import json
import matplotlib.pyplot as plt
import numpy as np
import os
from datetime import datetime

try:
    # Set style for better-looking charts
    plt.style.use('seaborn')
    
    # Load and prepare data
    with open('$dataPath', 'r') as f:
        data = json.load(f)
    
    # Filter successful analyses only
    data = [item for item in data if item['Status'] == 'Success']
    
    if not data:
        raise ValueError("No successful analyses found for charting")
    
    # Prepare data arrays
    files = [item['FileName'] for item in data]
    size_reduction = [item['SizeReduction'] for item in data]
    vmaf = [item['VMAF'] for item in data]
    qp_score = [item['QPScore'] for item in data]
    bitrate = [item['ConvertedBitrate'] for item in data]
    
    # Create output directory
    output_dir = os.path.join('$ConvertedPath', 'Charts')
    os.makedirs(output_dir, exist_ok=True)
    
    # 1. Enhanced Compression Efficiency vs Quality Plot
    plt.figure(figsize=(12, 8))
    scatter = plt.scatter(size_reduction, vmaf, c=qp_score, 
                         cmap='viridis', alpha=0.7, s=100)
    plt.colorbar(scatter, label='Quality-per-bit Score')
    plt.xlabel('Size Reduction (%)')
    plt.ylabel('VMAF Score')
    plt.title('Compression Efficiency vs Quality')
    
    # Add quality threshold lines
    plt.axhline(y=95, color='g', linestyle='--', alpha=0.5, label='Excellent Quality (95)')
    plt.axhline(y=90, color='y', linestyle='--', alpha=0.5, label='Good Quality (90)')
    plt.legend()
    
    plt.grid(True, alpha=0.3)
    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, 'compression_quality.png'), dpi=150, bbox_inches='tight')
    plt.close()
    
    # 2. Enhanced Bitrate vs Quality Plot
    plt.figure(figsize=(12, 8))
    norm = plt.Normalize(min(size_reduction), max(size_reduction))
    scatter = plt.scatter(bitrate, vmaf, c=size_reduction, 
                         cmap='plasma', alpha=0.7, s=100, norm=norm)
    plt.colorbar(scatter, label='Size Reduction (%)')
    plt.xlabel('Converted Bitrate (kbps)')
    plt.ylabel('VMAF Score')
    plt.title('Bitrate vs Quality Analysis')
    
    # Add threshold lines
    plt.axhline(y=95, color='g', linestyle='--', alpha=0.5, label='Excellent Quality (95)')
    plt.axhline(y=90, color='y', linestyle='--', alpha=0.5, label='Good Quality (90)')
    plt.legend()
    
    plt.grid(True, alpha=0.3)
    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, 'bitrate_quality.png'), dpi=150, bbox_inches='tight')
    plt.close()
    
    # 3. Quality Distribution with Enhanced Styling
    plt.figure(figsize=(10, 6))
    n, bins, patches = plt.hist(vmaf, bins=20, color='skyblue', edgecolor='black')
    
    # Color bins based on quality thresholds
    for i in range(len(patches)):
        if bins[i] >= 95:
            patches[i].set_facecolor('#27ae60')  # Green for excellent
        elif bins[i] >= 90:
            patches[i].set_facecolor('#f1c40f')  # Yellow for good
        else:
            patches[i].set_facecolor('#e74c3c')  # Red for below threshold
    
    plt.axvline(x=95, color='g', linestyle='--', alpha=0.5, label='Excellent (95)')
    plt.axvline(x=90, color='y', linestyle='--', alpha=0.5, label='Good (90)')
    plt.xlabel('VMAF Score')
    plt.ylabel('Number of Files')
    plt.title('Quality Score Distribution')
    plt.legend()
    plt.grid(True, alpha=0.3)
    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, 'quality_distribution.png'), dpi=150, bbox_inches='tight')
    plt.close()
    
    # 4. Enhanced Compression Ratio Distribution
    plt.figure(figsize=(10, 6))
    comp_ratio = [item['CompressionRatio'] for item in data]
    plt.hist(comp_ratio, bins=20, color='lightgreen', edgecolor='black')
    plt.xlabel('Compression Ratio')
    plt.ylabel('Number of Files')
    plt.title('Compression Ratio Distribution')
    avg_ratio = np.mean(comp_ratio)
    plt.axvline(x=avg_ratio, color='r', linestyle='--', 
                label=f'Average ({avg_ratio:.2f}:1)')
    plt.legend()
    plt.grid(True, alpha=0.3)
    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, 'compression_distribution.png'), dpi=150, bbox_inches='tight')
    plt.close()
    
    # 5. New: Quality vs Compression Efficiency Matrix
    plt.figure(figsize=(12, 8))
    h = plt.hist2d(size_reduction, vmaf, bins=20, cmap='YlOrRd')
    plt.colorbar(h[3], label='Number of Files')
    plt.xlabel('Size Reduction (%)')
    plt.ylabel('VMAF Score')
    plt.title('Quality vs Compression Efficiency Distribution')
    plt.axhline(y=95, color='g', linestyle='--', alpha=0.5, label='Excellent Quality (95)')
    plt.axhline(y=90, color='y', linestyle='--', alpha=0.5, label='Good Quality (90)')
    plt.legend()
    plt.grid(True, alpha=0.3)
    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, 'quality_compression_matrix.png'), dpi=150, bbox_inches='tight')
    plt.close()
    
    print("Charts generated successfully")
    
except Exception as e:
    print(f"Error generating charts: {str(e)}")
    raise
"@

        $scriptPath = Join-Path $ConvertedPath "generate_charts.py"
        $pythonScript | Out-File -FilePath $scriptPath -Encoding utf8
        
        try {
            $output = python $scriptPath 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Log "Charts generated successfully in: $(Join-Path $ConvertedPath 'Charts')" -Level Info
                Write-Host "Charts generated successfully in: $(Join-Path $ConvertedPath 'Charts')" -ForegroundColor Cyan
            } else {
                throw "Python script failed with exit code $LASTEXITCODE`n$output"
            }
        } catch {
            Write-Log "Chart generation failed: $_" -Level Error
            Write-Warning "Chart generation failed: $_"
            throw
        } finally {
            Remove-Item $scriptPath -ErrorAction SilentlyContinue
            Remove-Item $dataPath -ErrorAction SilentlyContinue
        }
    } catch {
        Write-Log "Failed to generate charts: $_" -Level Error
        Write-Warning "Failed to generate charts: $_"
    }
}

# Final summary
$totalTime = [Math]::Round(((Get-Date) - $scriptStart).TotalMinutes, 2)
Write-Log "Analysis completed in ${totalTime} minutes" -Level Info
Write-Host "`nAnalysis completed in ${totalTime} minutes" -ForegroundColor Green