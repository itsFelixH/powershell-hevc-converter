# HEVC Converter GUI
# Modern Windows Forms interface for PowerShell HEVC Video Converter

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Global variables
$script:selectedFiles = @()
$script:outputFolder = ""
$script:isConverting = $false

# Create main form
$form = New-Object System.Windows.Forms.Form
$form.Text = "HEVC Video Converter"
$form.Size = New-Object System.Drawing.Size(800, 600)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 240)

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

# File list
$fileListBox = New-Object System.Windows.Forms.ListBox
$fileListBox.Location = New-Object System.Drawing.Point(10, 25)
$fileListBox.Size = New-Object System.Drawing.Size(580, 80)
$fileListBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$fileGroupBox.Controls.Add($fileListBox)

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
$progressGroupBox.Location = New-Object System.Drawing.Point(20, 380)
$progressGroupBox.Size = New-Object System.Drawing.Size(740, 100)
$progressGroupBox.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$form.Controls.Add($progressGroupBox)

# Progress bar
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(20, 30)
$progressBar.Size = New-Object System.Drawing.Size(500, 25)
$progressGroupBox.Controls.Add($progressBar)

# Progress label
$progressLabel = New-Object System.Windows.Forms.Label
$progressLabel.Text = "Ready to convert"
$progressLabel.Location = New-Object System.Drawing.Point(20, 60)
$progressLabel.Size = New-Object System.Drawing.Size(500, 20)
$progressGroupBox.Controls.Add($progressLabel)

# Control buttons
$startBtn = New-Object System.Windows.Forms.Button
$startBtn.Text = "🚀 Start Conversion"
$startBtn.Location = New-Object System.Drawing.Point(540, 30)
$startBtn.Size = New-Object System.Drawing.Size(140, 40)
$startBtn.BackColor = [System.Drawing.Color]::FromArgb(46, 204, 113)
$startBtn.ForeColor = [System.Drawing.Color]::White
$startBtn.FlatStyle = "Flat"
$startBtn.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$progressGroupBox.Controls.Add($startBtn)

# Status bar
$statusStrip = New-Object System.Windows.Forms.StatusStrip
$statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusLabel.Text = "Ready"
$statusStrip.Items.Add($statusLabel)
$form.Controls.Add($statusStrip)

# Event handlers
$addFilesBtn.Add_Click({
    $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $openFileDialog.Filter = "Video Files|*.mkv;*.mp4;*.mov;*.wmv;*.avi;*.flv;*.m4v|All Files|*.*"
    $openFileDialog.Multiselect = $true
    $openFileDialog.Title = "Select Video Files to Convert"
    
    if ($openFileDialog.ShowDialog() -eq "OK") {
        foreach ($file in $openFileDialog.FileNames) {
            if ($script:selectedFiles -notcontains $file) {
                $script:selectedFiles += $file
                $fileListBox.Items.Add([System.IO.Path]::GetFileName($file))
            }
        }
        $statusLabel.Text = "Added $($openFileDialog.FileNames.Count) file(s)"
    }
})

$clearFilesBtn.Add_Click({
    $script:selectedFiles = @()
    $fileListBox.Items.Clear()
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

$startBtn.Add_Click({
    if ($script:selectedFiles.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Please select video files to convert.", "No Files Selected", "OK", "Warning")
        return
    }
    
    if ($script:isConverting) {
        [System.Windows.Forms.MessageBox]::Show("Conversion is already in progress.", "Already Converting", "OK", "Information")
        return
    }
    
    # Build PowerShell command
    $scriptPath = Join-Path $PSScriptRoot "Convert-VideoToHEVC.ps1"
    if (-not (Test-Path $scriptPath)) {
        [System.Windows.Forms.MessageBox]::Show("Convert-VideoToHEVC.ps1 not found in the same directory.", "Script Not Found", "OK", "Error")
        return
    }
    
    $script:isConverting = $true
    $startBtn.Enabled = $false
    $progressLabel.Text = "Starting conversion..."
    $statusLabel.Text = "Converting..."
    
    # Create temporary folder with selected files
    $tempFolder = New-Item -ItemType Directory -Path (Join-Path $env:TEMP "HEVCConverter_$(Get-Date -Format 'yyyyMMdd_HHmmss')") -Force
    foreach ($file in $script:selectedFiles) {
        Copy-Item $file $tempFolder.FullName
    }
    
    # Build parameters
    $params = @{
        inputFolder = $tempFolder.FullName
        outputFolder = $outputTextBox.Text
        crf = [int]$crfNumeric.Value
        preset = $presetComboBox.SelectedItem.ToString()
    }
    
    if ($profileComboBox.SelectedIndex -gt 0) {
        $params.Profile = $profileComboBox.SelectedItem.ToString()
    }
    
    if ($debugCheckBox.Checked) {
        $params.DebugMode = $true
    }
    
    if ($logCheckBox.Checked) {
        $params.LogToFile = $true
    }
    
    # Start conversion in background
    $job = Start-Job -ScriptBlock {
        param($ScriptPath, $Parameters)
        & $ScriptPath @Parameters
    } -ArgumentList $scriptPath, $params
    
    # Monitor progress
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 1000
    $timer.Add_Tick({
        if ($job.State -eq "Completed") {
            $timer.Stop()
            $script:isConverting = $false
            $startBtn.Enabled = $true
            $progressBar.Value = 100
            $progressLabel.Text = "Conversion completed!"
            $statusLabel.Text = "Ready"
            
            # Cleanup
            Remove-Item $tempFolder.FullName -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Job $job
            
            [System.Windows.Forms.MessageBox]::Show("Video conversion completed successfully!", "Conversion Complete", "OK", "Information")
        }
        elseif ($job.State -eq "Failed") {
            $timer.Stop()
            $script:isConverting = $false
            $startBtn.Enabled = $true
            $progressLabel.Text = "Conversion failed!"
            $statusLabel.Text = "Error"
            
            # Cleanup
            Remove-Item $tempFolder.FullName -Recurse -Force -ErrorAction SilentlyContinue
            $error = Receive-Job $job
            Remove-Job $job
            
            [System.Windows.Forms.MessageBox]::Show("Conversion failed. Check the log for details.", "Conversion Failed", "OK", "Error")
        }
        else {
            # Update progress (simplified)
            $currentProgress = $progressBar.Value + 2
            if ($currentProgress -lt 95) {
                $progressBar.Value = $currentProgress
            }
            $progressLabel.Text = "Converting... ($($script:selectedFiles.Count) files)"
        }
    })
    $timer.Start()
})

# Show form
$form.ShowDialog()