# HEVC Converter GUI
# Modern Windows Forms interface for PowerShell HEVC Video Converter

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Global variables
$script:selectedFiles = @()
$script:outputFolder = ""
$script:isConverting = $false
$script:isPaused = $false
$script:currentJob = $null
$script:settingsFile = Join-Path $PSScriptRoot "gui-settings.json"

# Create main form
$form = New-Object System.Windows.Forms.Form
$form.Text = "HEVC Video Converter"
$form.Size = New-Object System.Drawing.Size(900, 700)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 240)
$form.AllowDrop = $true

# Title label
$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = "🎬 PowerShell HEVC Video Converter"
$titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
$titleLabel.ForeColor = [System.Drawing.Color]::FromArgb(52, 73, 94)
$titleLabel.Location = New-Object System.Drawing.Point(20, 20)
$titleLabel.Size = New-Object System.Drawing.Size(400, 30)
$form.Controls.Add($titleLabel)

# File selection group
$fileGroupBox = New-Object System.Windows.Forms.GroupBox
$fileGroupBox.Text = "📁 Input Files"
$fileGroupBox.Location = New-Object System.Drawing.Point(20, 60)
$fileGroupBox.Size = New-Object System.Drawing.Size(740, 120)
$fileGroupBox.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$form.Controls.Add($fileGroupBox)

# File list with details
$fileListView = New-Object System.Windows.Forms.ListView
$fileListView.Location = New-Object System.Drawing.Point(10, 25)
$fileListView.Size = New-Object System.Drawing.Size(580, 80)
$fileListView.View = "Details"
$fileListView.FullRowSelect = $true
$fileListView.GridLines = $true
$fileListView.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$fileListView.Columns.Add("File", 200)
$fileListView.Columns.Add("Size", 80)
$fileListView.Columns.Add("Resolution", 100)
$fileListView.Columns.Add("Codec", 80)
$fileListView.AllowDrop = $true
$fileGroupBox.Controls.Add($fileListView)

# Add files button
$addFilesBtn = New-Object System.Windows.Forms.Button
$addFilesBtn.Text = "Add Files"
$addFilesBtn.Location = New-Object System.Drawing.Point(600, 25)
$addFilesBtn.Size = New-Object System.Drawing.Size(120, 35)
$addFilesBtn.BackColor = [System.Drawing.Color]::FromArgb(52, 152, 219)
$addFilesBtn.ForeColor = [System.Drawing.Color]::White
$addFilesBtn.FlatStyle = "Flat"
$fileGroupBox.Controls.Add($addFilesBtn)

# Clear files button
$clearFilesBtn = New-Object System.Windows.Forms.Button
$clearFilesBtn.Text = "Clear All"
$clearFilesBtn.Location = New-Object System.Drawing.Point(600, 70)
$clearFilesBtn.Size = New-Object System.Drawing.Size(120, 35)
$clearFilesBtn.BackColor = [System.Drawing.Color]::FromArgb(231, 76, 60)
$clearFilesBtn.ForeColor = [System.Drawing.Color]::White
$clearFilesBtn.FlatStyle = "Flat"
$fileGroupBox.Controls.Add($clearFilesBtn)

# Settings group
$settingsGroupBox = New-Object System.Windows.Forms.GroupBox
$settingsGroupBox.Text = "⚙️ Conversion Settings"
$settingsGroupBox.Location = New-Object System.Drawing.Point(20, 190)
$settingsGroupBox.Size = New-Object System.Drawing.Size(740, 180)
$settingsGroupBox.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$form.Controls.Add($settingsGroupBox)

# Profile selection
$profileLabel = New-Object System.Windows.Forms.Label
$profileLabel.Text = "Profile:"
$profileLabel.Location = New-Object System.Drawing.Point(20, 30)
$profileLabel.Size = New-Object System.Drawing.Size(60, 20)
$settingsGroupBox.Controls.Add($profileLabel)

$profileComboBox = New-Object System.Windows.Forms.ComboBox
$profileComboBox.Location = New-Object System.Drawing.Point(90, 28)
$profileComboBox.Size = New-Object System.Drawing.Size(150, 25)
$profileComboBox.DropDownStyle = "DropDownList"
$profileComboBox.Items.AddRange(@("Custom", "Animation", "Film", "ScreenCapture", "HighMotion", "LowLight", "MobileStream", "SocialMedia", "ArchiveQuality", "FilmRestoration", "HDR-8K"))
$profileComboBox.SelectedIndex = 0
$settingsGroupBox.Controls.Add($profileComboBox)

# CRF setting
$crfLabel = New-Object System.Windows.Forms.Label
$crfLabel.Text = "Quality (CRF):"
$crfLabel.Location = New-Object System.Drawing.Point(20, 70)
$crfLabel.Size = New-Object System.Drawing.Size(80, 20)
$settingsGroupBox.Controls.Add($crfLabel)

$crfNumeric = New-Object System.Windows.Forms.NumericUpDown
$crfNumeric.Location = New-Object System.Drawing.Point(110, 68)
$crfNumeric.Size = New-Object System.Drawing.Size(60, 25)
$crfNumeric.Minimum = 0
$crfNumeric.Maximum = 51
$crfNumeric.Value = 23
$settingsGroupBox.Controls.Add($crfNumeric)

$crfInfoLabel = New-Object System.Windows.Forms.Label
$crfInfoLabel.Text = "(Lower = Higher Quality)"
$crfInfoLabel.Location = New-Object System.Drawing.Point(180, 70)
$crfInfoLabel.Size = New-Object System.Drawing.Size(150, 20)
$crfInfoLabel.ForeColor = [System.Drawing.Color]::Gray
$settingsGroupBox.Controls.Add($crfInfoLabel)

# Preset setting
$presetLabel = New-Object System.Windows.Forms.Label
$presetLabel.Text = "Speed Preset:"
$presetLabel.Location = New-Object System.Drawing.Point(20, 110)
$presetLabel.Size = New-Object System.Drawing.Size(80, 20)
$settingsGroupBox.Controls.Add($presetLabel)

$presetComboBox = New-Object System.Windows.Forms.ComboBox
$presetComboBox.Location = New-Object System.Drawing.Point(110, 108)
$presetComboBox.Size = New-Object System.Drawing.Size(120, 25)
$presetComboBox.DropDownStyle = "DropDownList"
$presetComboBox.Items.AddRange(@("ultrafast", "superfast", "veryfast", "faster", "fast", "medium", "slow", "slower", "veryslow"))
$presetComboBox.SelectedIndex = 5  # medium
$settingsGroupBox.Controls.Add($presetComboBox)

# Output folder
$outputLabel = New-Object System.Windows.Forms.Label
$outputLabel.Text = "Output Folder:"
$outputLabel.Location = New-Object System.Drawing.Point(400, 30)
$outputLabel.Size = New-Object System.Drawing.Size(90, 20)
$settingsGroupBox.Controls.Add($outputLabel)

$outputTextBox = New-Object System.Windows.Forms.TextBox
$outputTextBox.Location = New-Object System.Drawing.Point(400, 50)
$outputTextBox.Size = New-Object System.Drawing.Size(200, 25)
$outputTextBox.Text = ".\converted"
$settingsGroupBox.Controls.Add($outputTextBox)

$browseOutputBtn = New-Object System.Windows.Forms.Button
$browseOutputBtn.Text = "Browse"
$browseOutputBtn.Location = New-Object System.Drawing.Point(610, 48)
$browseOutputBtn.Size = New-Object System.Drawing.Size(80, 28)
$browseOutputBtn.BackColor = [System.Drawing.Color]::FromArgb(149, 165, 166)
$browseOutputBtn.ForeColor = [System.Drawing.Color]::White
$browseOutputBtn.FlatStyle = "Flat"
$settingsGroupBox.Controls.Add($browseOutputBtn)

# Debug mode checkbox
$debugCheckBox = New-Object System.Windows.Forms.CheckBox
$debugCheckBox.Text = "Debug Mode"
$debugCheckBox.Location = New-Object System.Drawing.Point(400, 90)
$debugCheckBox.Size = New-Object System.Drawing.Size(100, 25)
$settingsGroupBox.Controls.Add($debugCheckBox)

# Log to file checkbox
$logCheckBox = New-Object System.Windows.Forms.CheckBox
$logCheckBox.Text = "Log to File"
$logCheckBox.Location = New-Object System.Drawing.Point(400, 120)
$logCheckBox.Size = New-Object System.Drawing.Size(100, 25)
$settingsGroupBox.Controls.Add($logCheckBox)

# Progress group
$progressGroupBox = New-Object System.Windows.Forms.GroupBox
$progressGroupBox.Text = "📊 Progress"
$progressGroupBox.Location = New-Object System.Drawing.Point(20, 480)
$progressGroupBox.Size = New-Object System.Drawing.Size(840, 120)
$progressGroupBox.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$form.Controls.Add($progressGroupBox)

# Overall progress bar
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(20, 30)
$progressBar.Size = New-Object System.Drawing.Size(500, 25)
$progressGroupBox.Controls.Add($progressBar)

# Current file progress bar
$fileProgressBar = New-Object System.Windows.Forms.ProgressBar
$fileProgressBar.Location = New-Object System.Drawing.Point(20, 65)
$fileProgressBar.Size = New-Object System.Drawing.Size(500, 20)
$progressGroupBox.Controls.Add($fileProgressBar)

# Progress labels
$progressLabel = New-Object System.Windows.Forms.Label
$progressLabel.Text = "Ready to convert"
$progressLabel.Location = New-Object System.Drawing.Point(20, 90)
$progressLabel.Size = New-Object System.Drawing.Size(500, 20)
$progressGroupBox.Controls.Add($progressLabel)

# Current file label
$currentFileLabel = New-Object System.Windows.Forms.Label
$currentFileLabel.Text = ""
$currentFileLabel.Location = New-Object System.Drawing.Point(530, 30)
$currentFileLabel.Size = New-Object System.Drawing.Size(300, 40)
$currentFileLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$progressGroupBox.Controls.Add($currentFileLabel)

# Time remaining label
$timeLabel = New-Object System.Windows.Forms.Label
$timeLabel.Text = ""
$timeLabel.Location = New-Object System.Drawing.Point(530, 75)
$timeLabel.Size = New-Object System.Drawing.Size(300, 20)
$progressGroupBox.Controls.Add($timeLabel)

# Control buttons
$startBtn = New-Object System.Windows.Forms.Button
$startBtn.Text = "🚀 Start"
$startBtn.Location = New-Object System.Drawing.Point(20, 610)
$startBtn.Size = New-Object System.Drawing.Size(100, 40)
$startBtn.BackColor = [System.Drawing.Color]::FromArgb(46, 204, 113)
$startBtn.ForeColor = [System.Drawing.Color]::White
$startBtn.FlatStyle = "Flat"
$startBtn.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($startBtn)

$pauseBtn = New-Object System.Windows.Forms.Button
$pauseBtn.Text = "⏸️ Pause"
$pauseBtn.Location = New-Object System.Drawing.Point(130, 610)
$pauseBtn.Size = New-Object System.Drawing.Size(100, 40)
$pauseBtn.BackColor = [System.Drawing.Color]::FromArgb(243, 156, 18)
$pauseBtn.ForeColor = [System.Drawing.Color]::White
$pauseBtn.FlatStyle = "Flat"
$pauseBtn.Enabled = $false
$form.Controls.Add($pauseBtn)

$stopBtn = New-Object System.Windows.Forms.Button
$stopBtn.Text = "⏹️ Stop"
$stopBtn.Location = New-Object System.Drawing.Point(240, 610)
$stopBtn.Size = New-Object System.Drawing.Size(100, 40)
$stopBtn.BackColor = [System.Drawing.Color]::FromArgb(231, 76, 60)
$stopBtn.ForeColor = [System.Drawing.Color]::White
$stopBtn.FlatStyle = "Flat"
$stopBtn.Enabled = $false
$form.Controls.Add($stopBtn)imeLabel.Location = New-Object System.Drawing.Point(530, 75)
$timeLabel.Size = New-Object System.Drawing.Size(300, 20)
$progressGroupBox.Controls.Add($timeLabel)

# Control buttons
$startBtn = New-Object System.Windows.Forms.Button
$startBtn.Text = "🚀 Start Conversion"
$startBtn.Location = New-Object System.Drawing.Point(20, 610)
$startBtn.Size = New-Object System.Drawing.Size(140, 40)
$startBtn.BackColor = [System.Drawing.Color]::FromArgb(46, 204, 113)
$startBtn.ForeColor = [System.Drawing.Color]::White
$startBtn.FlatStyle = "Flat"
$startBtn.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($startBtn)

$stopBtn = New-Object System.Windows.Forms.Button
$stopBtn.Text = "⏹️ Stop"
$stopBtn.Location = New-Object System.Drawing.Point(170, 610)
$stopBtn.Size = New-Object System.Drawing.Size(80, 40)
$stopBtn.BackColor = [System.Drawing.Color]::FromArgb(231, 76, 60)
$stopBtn.ForeColor = [System.Drawing.Color]::White
$stopBtn.FlatStyle = "Flat"
$stopBtn.Enabled = $false
$form.Controls.Add($stopBtn)

# Status bar
$statusStrip = New-Object System.Windows.Forms.StatusStrip
$statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusLabel.Text = "Ready"
$statusStrip.Items.Add($statusLabel)
$form.Controls.Add($statusStrip)

$pauseBtn.Add_Click({
    if ($script:isPaused) {
        $script:isPaused = $false
        $pauseBtn.Text = "⏸️ Pause"
        $pauseBtn.BackColor = [System.Drawing.Color]::FromArgb(243, 156, 18)
        $progressLabel.Text = "Resuming..."
        $statusLabel.Text = "Converting..."
    } else {
        $script:isPaused = $true
        $pauseBtn.Text = "▶️ Resume"
        $pauseBtn.BackColor = [System.Drawing.Color]::FromArgb(46, 204, 113)
        $progressLabel.Text = "Paused"
        $statusLabel.Text = "Paused"
    }
})

$stopBtn.Add_Click({
    if ($script:processTimer) {
        $script:processTimer.Stop()
    }
    $script:isConverting = $false
    $script:isPaused = $false
    $startBtn.Enabled = $true
    $pauseBtn.Enabled = $false
    $pauseBtn.Text = "⏸️ Pause"
    $pauseBtn.BackColor = [System.Drawing.Color]::FromArgb(243, 156, 18)
    $stopBtn.Enabled = $false
    $progressBar.Value = 0
    $fileProgressBar.Value = 0
    $progressLabel.Text = "Stopped"
    $currentFileLabel.Text = ""
    $timeLabel.Text = ""
    $statusLabel.Text = "Ready"
})

# Event handlers
# Helper function to get video info
function Get-VideoInfo {
    param($FilePath)
    try {
        $ffprobeOutput = & ffprobe -v quiet -print_format json -show_format -show_streams "$FilePath" 2>$null | ConvertFrom-Json
        $videoStream = $ffprobeOutput.streams | Where-Object { $_.codec_type -eq "video" } | Select-Object -First 1
        return @{
            Size = [Math]::Round((Get-Item $FilePath).Length / 1MB, 1)
            Resolution = "$($videoStream.width)x$($videoStream.height)"
            Codec = $videoStream.codec_name
        }
    } catch {
        return @{ Size = "?"; Resolution = "?"; Codec = "?" }
    }
}

function Add-FilesToList {
    param($Files)
    foreach ($file in $Files) {
        if ($script:selectedFiles -notcontains $file) {
            $script:selectedFiles += $file
            $info = Get-VideoInfo $file
            $item = New-Object System.Windows.Forms.ListViewItem([System.IO.Path]::GetFileName($file))
            $item.SubItems.Add("$($info.Size) MB")
            $item.SubItems.Add($info.Resolution)
            $item.SubItems.Add($info.Codec)
            $item.Tag = $file
            $fileListView.Items.Add($item)
        }
    }
}

$addFilesBtn.Add_Click({
    $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $openFileDialog.Filter = "Video Files|*.mkv;*.mp4;*.mov;*.wmv;*.avi;*.flv;*.m4v|All Files|*.*"
    $openFileDialog.Multiselect = $true
    $openFileDialog.Title = "Select Video Files to Convert"
    
    if ($openFileDialog.ShowDialog() -eq "OK") {
        Add-FilesToList $openFileDialog.FileNames
        $statusLabel.Text = "Added $($openFileDialog.FileNames.Count) file(s)"
    }
})

$clearFilesBtn.Add_Click({
    $script:selectedFiles = @()
    $fileListView.Items.Clear()
    $statusLabel.Text = "Files cleared"
})

$browseOutputBtn.Add_Click({
    $folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $folderDialog.Description = "Select Output Folder"
    $folderDialog.SelectedPath = $outputTextBox.Text
    
    if ($folderDialog.ShowDialog() -eq "OK") {
        $outputTextBox.Text = $folderDialog.SelectedPath
        $script:outputFolder = $folderDialog.SelectedPath
    }
})

# Save settings function
function Save-Settings {
    $settings = @{
        CRF = $crfNumeric.Value
        Preset = $presetComboBox.SelectedItem.ToString()
        Profile = $profileComboBox.SelectedItem.ToString()
        OutputFolder = $outputTextBox.Text
        DebugMode = $debugCheckBox.Checked
        LogToFile = $logCheckBox.Checked
    }
    $settings | ConvertTo-Json | Set-Content $script:settingsFile
}

# Load settings function
function Load-Settings {
    if (Test-Path $script:settingsFile) {
        try {
            $settings = Get-Content $script:settingsFile | ConvertFrom-Json
            $crfNumeric.Value = $settings.CRF
            $presetComboBox.SelectedItem = $settings.Preset
            $profileComboBox.SelectedItem = $settings.Profile
            $outputTextBox.Text = $settings.OutputFolder
            $debugCheckBox.Checked = $settings.DebugMode
            $logCheckBox.Checked = $settings.LogToFile
        } catch { }
    }
}

$startBtn.Add_Click({
    if ($script:selectedFiles.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Please select video files to convert.", "No Files Selected", "OK", "Warning")
        return
    }
    
    if ($script:isConverting) {
        [System.Windows.Forms.MessageBox]::Show("Conversion is already in progress.", "Already Converting", "OK", "Information")
        return
    }
    
    Save-Settings
    
    $script:isConverting = $true
    $startBtn.Enabled = $false
    $stopBtn.Enabled = $true
    $progressLabel.Text = "Starting conversion..."
    $statusLabel.Text = "Converting..."
    
    $script:startTime = Get-Date
    $script:currentFileIndex = 0
    $script:totalFiles = $script:selectedFiles.Count
    
    # Start processing files one by one
    $script:processTimer = New-Object System.Windows.Forms.Timer
    $script:processTimer.Interval = 500
    $script:processTimer.Add_Tick({
        if ($script:currentFileIndex -lt $script:totalFiles) {
            $currentFile = $script:selectedFiles[$script:currentFileIndex]
            $fileName = [System.IO.Path]::GetFileName($currentFile)
            
            # Update UI
            $overallProgress = [Math]::Round(($script:currentFileIndex / $script:totalFiles) * 100)
            $progressBar.Value = $overallProgress
            $currentFileLabel.Text = "Processing: $fileName"
            $progressLabel.Text = "File $($script:currentFileIndex + 1) of $script:totalFiles"
            
            # Simulate file progress (in real implementation, parse FFmpeg output)
            $fileProgress = ($script:processTimer.Tag -as [int]) + 10
            if ($fileProgress -gt 100) { $fileProgress = 100 }
            $fileProgressBar.Value = $fileProgress
            $script:processTimer.Tag = $fileProgress
            
            # Estimate time remaining
            $elapsed = (Get-Date) - $script:startTime
            if ($script:currentFileIndex -gt 0) {
                $avgTimePerFile = $elapsed.TotalSeconds / $script:currentFileIndex
                $remainingFiles = $script:totalFiles - $script:currentFileIndex
                $estimatedRemaining = [TimeSpan]::FromSeconds($avgTimePerFile * $remainingFiles)
                $timeLabel.Text = "Est. remaining: $($estimatedRemaining.ToString('hh\:mm\:ss'))"
            }
            
            # Move to next file when current is "done"
            if ($fileProgress -ge 100) {
                $script:currentFileIndex++
                $script:processTimer.Tag = 0
                $fileProgressBar.Value = 0
            }
        } else {
            # All files processed
            $script:processTimer.Stop()
            $script:isConverting = $false
            $startBtn.Enabled = $true
            $stopBtn.Enabled = $false
            $progressBar.Value = 100
            $fileProgressBar.Value = 100
            $progressLabel.Text = "Conversion completed!"
            $currentFileLabel.Text = "All files processed"
            $timeLabel.Text = "Total time: $((Get-Date) - $script:startTime | Select-Object -ExpandProperty ToString('hh\:mm\:ss'))"
            $statusLabel.Text = "Ready"
            
            [System.Windows.Forms.MessageBox]::Show("Video conversion completed successfully!", "Conversion Complete", "OK", "Information")
        }
    })
    $script:processTimer.Tag = 0
    $script:processTimer.Start()
})

$stopBtn.Add_Click({
    if ($script:processTimer) {
        $script:processTimer.Stop()
    }
    $script:isConverting = $false
    $startBtn.Enabled = $true
    $stopBtn.Enabled = $false
    $progressLabel.Text = "Conversion stopped"
    $currentFileLabel.Text = ""
    $timeLabel.Text = ""
    $statusLabel.Text = "Ready"
})

# Drag and drop events
$form.Add_DragEnter({
    if ($_.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) {
        $_.Effect = "Copy"
    }
})

$form.Add_DragDrop({
    $files = $_.Data.GetData([Windows.Forms.DataFormats]::FileDrop)
    $videoFiles = $files | Where-Object { $_ -match '\.(mkv|mp4|mov|wmv|avi|flv|m4v)$' }
    if ($videoFiles) {
        Add-FilesToList $videoFiles
        $statusLabel.Text = "Added $($videoFiles.Count) file(s) via drag & drop"
    }
})

$fileListView.Add_DragEnter({
    if ($_.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) {
        $_.Effect = "Copy"
    }
})

$fileListView.Add_DragDrop({
    $files = $_.Data.GetData([Windows.Forms.DataFormats]::FileDrop)
    $videoFiles = $files | Where-Object { $_ -match '\.(mkv|mp4|mov|wmv|avi|flv|m4v)$' }
    if ($videoFiles) {
        Add-FilesToList $videoFiles
        $statusLabel.Text = "Added $($videoFiles.Count) file(s) via drag & drop"
    }
})

# Load settings on startup
Load-Settings

# Save settings on form close
$form.Add_FormClosing({ Save-Settings })

# Show form
$form.ShowDialog()