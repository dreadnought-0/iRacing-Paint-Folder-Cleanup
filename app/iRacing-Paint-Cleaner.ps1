# =============================================================================
# iRacing Paint Folder Cleaner
# =============================================================================

# --- Configuration -----------------------------------------------------------
$script:ApiBaseUrl      = "https://paint-cleaner-api.flare.darkspacelabs.com"
$script:ApiSecret       = "ce75d72769d7fedf1051d2bc634fb6b574fcd609ff2c2db49ba84a085eb8363f"
$script:DefaultPaints   = Join-Path $env:USERPROFILE "Documents\iRacing\paint"
$script:LicenseFile     = "$env:APPDATA\iRacingPaintCleaner\license.enc"
$script:GracePeriodDays = 7
$script:RevalidateHours = 24
# -----------------------------------------------------------------------------

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Security

# =============================================================================
# LICENSE MANAGER
# =============================================================================

function Get-MachineId {
    try {
        $cpu  = (Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1).ProcessorId
        $mobo = (Get-CimInstance Win32_BaseBoard -ErrorAction Stop).SerialNumber
        $raw  = "$cpu|$mobo"
    } catch {
        # Fallback: registry machine GUID + username
        $guid = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Cryptography" -Name MachineGuid -ErrorAction SilentlyContinue).MachineGuid
        $raw  = "$guid|$env:USERNAME"
    }
    $sha   = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($raw)
    return ([System.BitConverter]::ToString($sha.ComputeHash($bytes)) -replace "-", "").ToLower()
}

function Save-License {
    param([string]$Key, [string]$MachineId, [string]$Plan, [string]$ExpiresAt)
    $data  = @{ key = $Key; machine_id = $MachineId; plan = $Plan; expires_at = $ExpiresAt; last_validated = [datetime]::UtcNow.ToString("o") }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($data | ConvertTo-Json -Compress))
    $enc   = [System.Security.Cryptography.ProtectedData]::Protect($bytes, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
    $dir   = [System.IO.Path]::GetDirectoryName($script:LicenseFile)
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllBytes($script:LicenseFile, $enc)
}

function Load-License {
    if (-not (Test-Path $script:LicenseFile)) { return $null }
    try {
        $enc  = [System.IO.File]::ReadAllBytes($script:LicenseFile)
        $dec  = [System.Security.Cryptography.ProtectedData]::Unprotect($enc, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
        return ([System.Text.Encoding]::UTF8.GetString($dec) | ConvertFrom-Json)
    } catch { return $null }
}

function Remove-License {
    if (Test-Path $script:LicenseFile) { Remove-Item $script:LicenseFile -Force }
}

function Invoke-Api {
    param([string]$Endpoint, [hashtable]$Body)
    try {
        $resp = Invoke-RestMethod `
            -Uri "$($script:ApiBaseUrl)/$Endpoint" `
            -Method Post `
            -Body ($Body | ConvertTo-Json) `
            -ContentType "application/json" `
            -Headers @{ "X-API-Key" = $script:ApiSecret } `
            -TimeoutSec 10
        return $resp
    } catch { return $null }
}

# Returns hashtable with Status: OK | NoLicense | Invalid | Grace | GraceExpired
function Test-License {
    $mid = Get-MachineId
    $lic = Load-License
    if (-not $lic) { return @{ Status = "NoLicense" } }

    $hoursSince = ([datetime]::UtcNow - [datetime]::Parse($lic.last_validated)).TotalHours
    if ($hoursSince -lt $script:RevalidateHours) {
        return @{ Status = "OK"; Data = $lic }
    }

    $resp = Invoke-Api "api/validate" @{ key = $lic.key; machine_id = $mid }

    if ($resp) {
        if ($resp.valid -eq $true) {
            Save-License $lic.key $mid $resp.plan $resp.expires_at
            return @{ Status = "OK"; Data = $lic }
        } else {
            Remove-License
            return @{ Status = "Invalid"; Message = $resp.message }
        }
    } else {
        $daysSince = ([datetime]::UtcNow - [datetime]::Parse($lic.last_validated)).TotalDays
        if ($daysSince -lt $script:GracePeriodDays) {
            return @{ Status = "Grace"; DaysLeft = [math]::Ceiling($script:GracePeriodDays - $daysSince); Data = $lic }
        } else {
            Remove-License
            return @{ Status = "GraceExpired" }
        }
    }
}

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

function Get-PaintStats {
    param([string]$Path)
    $carFolders = Get-ChildItem -Path $Path -Directory -ErrorAction SilentlyContinue
    $totalFiles = 0; $totalBytes = 0
    foreach ($f in $carFolders) {
        $files = Get-ChildItem -Path $f.FullName -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer }
        $totalFiles += $files.Count
        $totalBytes += ($files | Measure-Object -Property Length -Sum).Sum
    }
    return @{ Folders = $carFolders.Count; Files = $totalFiles; Bytes = $totalBytes }
}

function Format-Bytes {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return "$([math]::Round($Bytes/1GB,2)) GB" }
    if ($Bytes -ge 1MB) { return "$([math]::Round($Bytes/1MB,2)) MB" }
    if ($Bytes -ge 1KB) { return "$([math]::Round($Bytes/1KB,2)) KB" }
    return "$Bytes B"
}

# =============================================================================
# ACTIVATION FORM
# =============================================================================

function Show-ActivationForm {
    param([string]$StatusMessage = "")

    $frm = New-Object System.Windows.Forms.Form
    $frm.Text            = "iRacing Paint Cleaner - Activate"
    $frm.Size            = New-Object System.Drawing.Size(460, 300)
    $frm.StartPosition   = "CenterScreen"
    $frm.FormBorderStyle = "FixedSingle"
    $frm.MaximizeBox     = $false
    $frm.BackColor       = [System.Drawing.Color]::FromArgb(24, 24, 24)
    $frm.ForeColor       = [System.Drawing.Color]::FromArgb(220, 220, 220)
    $frm.Font            = New-Object System.Drawing.Font("Segoe UI", 9)

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text      = "Activate Your License"
    $lblTitle.Font      = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold)
    $lblTitle.ForeColor = [System.Drawing.Color]::FromArgb(0, 180, 255)
    $lblTitle.Location  = New-Object System.Drawing.Point(20, 20)
    $lblTitle.Size      = New-Object System.Drawing.Size(400, 28)
    $frm.Controls.Add($lblTitle)

    $lblSub = New-Object System.Windows.Forms.Label
    $lblSub.Text      = "Enter the license key from your purchase confirmation."
    $lblSub.ForeColor = [System.Drawing.Color]::FromArgb(150, 150, 150)
    $lblSub.Location  = New-Object System.Drawing.Point(20, 54)
    $lblSub.Size      = New-Object System.Drawing.Size(410, 18)
    $frm.Controls.Add($lblSub)

    $lblKey = New-Object System.Windows.Forms.Label
    $lblKey.Text     = "License Key"
    $lblKey.Font     = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $lblKey.ForeColor = [System.Drawing.Color]::FromArgb(150, 150, 150)
    $lblKey.Location = New-Object System.Drawing.Point(20, 90)
    $lblKey.Size     = New-Object System.Drawing.Size(200, 16)
    $frm.Controls.Add($lblKey)

    $txtKey = New-Object System.Windows.Forms.TextBox
    $txtKey.Location    = New-Object System.Drawing.Point(20, 110)
    $txtKey.Size        = New-Object System.Drawing.Size(410, 24)
    $txtKey.Font        = New-Object System.Drawing.Font("Consolas", 11)
    $txtKey.BackColor   = [System.Drawing.Color]::FromArgb(40, 40, 40)
    $txtKey.ForeColor   = [System.Drawing.Color]::FromArgb(220, 220, 220)
    $txtKey.BorderStyle = "FixedSingle"
    $txtKey.MaxLength   = 26
    $txtKey.CharacterCasing = "Upper"
    $frm.Controls.Add($txtKey)

    $lblStatus = New-Object System.Windows.Forms.Label
    $lblStatus.Text      = $StatusMessage
    $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(255, 80, 80)
    $lblStatus.Location  = New-Object System.Drawing.Point(20, 144)
    $lblStatus.Size      = New-Object System.Drawing.Size(410, 18)
    $frm.Controls.Add($lblStatus)

    $btnActivate = New-Object System.Windows.Forms.Button
    $btnActivate.Text      = "Activate"
    $btnActivate.Location  = New-Object System.Drawing.Point(20, 172)
    $btnActivate.Size      = New-Object System.Drawing.Size(410, 40)
    $btnActivate.FlatStyle = "Flat"
    $btnActivate.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $btnActivate.ForeColor = [System.Drawing.Color]::White
    $btnActivate.Font      = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnActivate.FlatAppearance.BorderSize = 0
    $frm.Controls.Add($btnActivate)

    $lblHelp = New-Object System.Windows.Forms.Label
    $lblHelp.Text      = "Lost your key? Contact support."
    $lblHelp.ForeColor = [System.Drawing.Color]::FromArgb(100, 100, 100)
    $lblHelp.Location  = New-Object System.Drawing.Point(20, 226)
    $lblHelp.Size      = New-Object System.Drawing.Size(410, 18)
    $frm.Controls.Add($lblHelp)

    $activated = $false

    $btnActivate.Add_Click({
        $key = $txtKey.Text.Trim()
        if ($key.Length -lt 10) {
            $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(255, 80, 80)
            $lblStatus.Text = "Please enter a valid license key."
            return
        }

        $btnActivate.Enabled = $false
        $btnActivate.Text    = "Activating..."
        $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(150, 150, 150)
        $lblStatus.Text      = "Contacting server..."
        $frm.Refresh()

        $mid  = Get-MachineId
        $resp = Invoke-Api "api/activate" @{ key = $key; machine_id = $mid }

        if ($resp -and $resp.success -eq $true) {
            Save-License $key $mid $resp.plan $resp.expires_at
            $script:activated = $true
            $frm.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $frm.Close()
        } else {
            $msg = if ($resp -and $resp.message) { $resp.message } else { "Could not reach activation server. Check your internet connection." }
            $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(255, 80, 80)
            $lblStatus.Text      = $msg
            $btnActivate.Enabled = $true
            $btnActivate.Text    = "Activate"
        }
    })

    $txtKey.Add_KeyDown({
        if ($_.KeyCode -eq "Return") { $btnActivate.PerformClick() }
    })

    $result = $frm.ShowDialog()
    return ($result -eq [System.Windows.Forms.DialogResult]::OK)
}

# =============================================================================
# MAIN APP FORM
# =============================================================================

function Show-MainForm {
    param([hashtable]$LicenseStatus)

    $form = New-Object System.Windows.Forms.Form
    $form.Text           = "iRacing Paint Folder Cleaner"
    $form.Size           = New-Object System.Drawing.Size(540, 480)
    $form.MinimumSize    = New-Object System.Drawing.Size(540, 480)
    $form.StartPosition  = "CenterScreen"
    $form.FormBorderStyle = "Sizable"
    $form.MaximizeBox    = $false
    $form.BackColor      = [System.Drawing.Color]::FromArgb(24, 24, 24)
    $form.ForeColor      = [System.Drawing.Color]::FromArgb(220, 220, 220)
    $form.Font           = New-Object System.Drawing.Font("Segoe UI", 9)

    # Header
    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text      = "iRacing Paint Folder Cleaner"
    $lblTitle.Font      = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $lblTitle.ForeColor = [System.Drawing.Color]::FromArgb(0, 180, 255)
    $lblTitle.Location  = New-Object System.Drawing.Point(16, 16)
    $lblTitle.Size      = New-Object System.Drawing.Size(400, 30)
    $form.Controls.Add($lblTitle)

    # License status badge
    $licText  = if ($LicenseStatus.Data) { "$($LicenseStatus.Data.plan)" } else { "Active" }
    $licColor = if ($LicenseStatus.Status -eq "Grace") { [System.Drawing.Color]::FromArgb(255,180,0) } else { [System.Drawing.Color]::FromArgb(0,200,100) }
    $lblLic = New-Object System.Windows.Forms.Label
    $lblLic.Text      = $licText.ToUpper()
    $lblLic.Font      = New-Object System.Drawing.Font("Segoe UI", 7, [System.Drawing.FontStyle]::Bold)
    $lblLic.ForeColor = $licColor
    $lblLic.Location  = New-Object System.Drawing.Point(16, 50)
    $lblLic.Size      = New-Object System.Drawing.Size(500, 16)
    $form.Controls.Add($lblLic)

    if ($LicenseStatus.Status -eq "Grace") {
        $lblLic.Text = "OFFLINE MODE - license check due (server unreachable) - $($LicenseStatus.DaysLeft) day(s) remaining"
    }

    # Folder row
    $lblFolderHeader = New-Object System.Windows.Forms.Label
    $lblFolderHeader.Text      = "Paints Folder"
    $lblFolderHeader.Font      = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $lblFolderHeader.ForeColor = [System.Drawing.Color]::FromArgb(150, 150, 150)
    $lblFolderHeader.Location  = New-Object System.Drawing.Point(16, 80)
    $lblFolderHeader.Size      = New-Object System.Drawing.Size(200, 16)
    $form.Controls.Add($lblFolderHeader)

    $txtFolder = New-Object System.Windows.Forms.TextBox
    $txtFolder.Text        = $script:DefaultPaints
    $txtFolder.Location    = New-Object System.Drawing.Point(16, 100)
    $txtFolder.Size        = New-Object System.Drawing.Size(408, 24)
    $txtFolder.BackColor   = [System.Drawing.Color]::FromArgb(40, 40, 40)
    $txtFolder.ForeColor   = [System.Drawing.Color]::FromArgb(220, 220, 220)
    $txtFolder.BorderStyle = "FixedSingle"
    $form.Controls.Add($txtFolder)

    $btnBrowse = New-Object System.Windows.Forms.Button
    $btnBrowse.Text      = "Browse..."
    $btnBrowse.Location  = New-Object System.Drawing.Point(432, 99)
    $btnBrowse.Size      = New-Object System.Drawing.Size(82, 26)
    $btnBrowse.FlatStyle = "Flat"
    $btnBrowse.BackColor = [System.Drawing.Color]::FromArgb(50, 50, 50)
    $btnBrowse.ForeColor = [System.Drawing.Color]::FromArgb(220, 220, 220)
    $btnBrowse.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(80, 80, 80)
    $form.Controls.Add($btnBrowse)

    # Stats panel
    $panelStats = New-Object System.Windows.Forms.Panel
    $panelStats.Location  = New-Object System.Drawing.Point(16, 140)
    $panelStats.Size      = New-Object System.Drawing.Size(498, 60)
    $panelStats.BackColor = [System.Drawing.Color]::FromArgb(35, 35, 35)
    $form.Controls.Add($panelStats)

    $lblStatFolders = New-Object System.Windows.Forms.Label
    $lblStatFolders.Text      = "Car folders: ..."
    $lblStatFolders.Location  = New-Object System.Drawing.Point(12, 10)
    $lblStatFolders.Size      = New-Object System.Drawing.Size(150, 20)
    $lblStatFolders.ForeColor = [System.Drawing.Color]::FromArgb(180, 180, 180)
    $panelStats.Controls.Add($lblStatFolders)

    $lblStatFiles = New-Object System.Windows.Forms.Label
    $lblStatFiles.Text      = "Paint files: ..."
    $lblStatFiles.Location  = New-Object System.Drawing.Point(170, 10)
    $lblStatFiles.Size      = New-Object System.Drawing.Size(150, 20)
    $lblStatFiles.ForeColor = [System.Drawing.Color]::FromArgb(180, 180, 180)
    $panelStats.Controls.Add($lblStatFiles)

    $lblStatSize = New-Object System.Windows.Forms.Label
    $lblStatSize.Text      = "Total size: ..."
    $lblStatSize.Location  = New-Object System.Drawing.Point(330, 10)
    $lblStatSize.Size      = New-Object System.Drawing.Size(150, 20)
    $lblStatSize.ForeColor = [System.Drawing.Color]::FromArgb(180, 180, 180)
    $panelStats.Controls.Add($lblStatSize)

    $btnScan = New-Object System.Windows.Forms.Button
    $btnScan.Text      = "Scan Folder"
    $btnScan.Location  = New-Object System.Drawing.Point(12, 34)
    $btnScan.Size      = New-Object System.Drawing.Size(100, 22)
    $btnScan.FlatStyle = "Flat"
    $btnScan.BackColor = [System.Drawing.Color]::FromArgb(50, 50, 50)
    $btnScan.ForeColor = [System.Drawing.Color]::FromArgb(220, 220, 220)
    $btnScan.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(80, 80, 80)
    $panelStats.Controls.Add($btnScan)

    # Log
    $lblLogHeader = New-Object System.Windows.Forms.Label
    $lblLogHeader.Text      = "Log"
    $lblLogHeader.Font      = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $lblLogHeader.ForeColor = [System.Drawing.Color]::FromArgb(150, 150, 150)
    $lblLogHeader.Location  = New-Object System.Drawing.Point(16, 214)
    $lblLogHeader.Size      = New-Object System.Drawing.Size(60, 16)
    $form.Controls.Add($lblLogHeader)

    $txtLog = New-Object System.Windows.Forms.RichTextBox
    $txtLog.Location    = New-Object System.Drawing.Point(16, 234)
    $txtLog.Size        = New-Object System.Drawing.Size(498, 140)
    $txtLog.ReadOnly    = $true
    $txtLog.BackColor   = [System.Drawing.Color]::FromArgb(16, 16, 16)
    $txtLog.ForeColor   = [System.Drawing.Color]::FromArgb(200, 200, 200)
    $txtLog.Font        = New-Object System.Drawing.Font("Consolas", 9)
    $txtLog.BorderStyle = "None"
    $txtLog.ScrollBars  = "Vertical"
    $txtLog.WordWrap    = $false
    $form.Controls.Add($txtLog)

    # Clean button
    $btnClean = New-Object System.Windows.Forms.Button
    $btnClean.Text      = "Clean Paint Files"
    $btnClean.Location  = New-Object System.Drawing.Point(16, 390)
    $btnClean.Size      = New-Object System.Drawing.Size(498, 44)
    $btnClean.FlatStyle = "Flat"
    $btnClean.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $btnClean.ForeColor = [System.Drawing.Color]::White
    $btnClean.Font      = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $btnClean.FlatAppearance.BorderSize = 0
    $btnClean.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $form.Controls.Add($btnClean)

    # Helpers
    function Write-Log {
        param([string]$Msg, [System.Drawing.Color]$Color = [System.Drawing.Color]::FromArgb(200,200,200))
        $txtLog.SelectionStart = $txtLog.TextLength; $txtLog.SelectionLength = 0
        $txtLog.SelectionColor = $Color
        $txtLog.AppendText("$Msg`n")
        $txtLog.ScrollToCaret()
    }

    function Update-Stats {
        param([string]$FolderPath)
        if (-not (Test-Path $FolderPath)) {
            $lblStatFolders.Text = "Car folders: ..."; $lblStatFiles.Text = "Paint files: ..."; $lblStatSize.Text = "Total size: ..."; return
        }
        $lblStatFolders.Text = "Scanning..."; $lblStatFiles.Text = ""; $lblStatSize.Text = ""; $form.Refresh()
        $s = Get-PaintStats $FolderPath
        $lblStatFolders.Text = "Car folders: $($s.Folders)"
        $lblStatFiles.Text   = "Paint files: $($s.Files)"
        $lblStatSize.Text    = "Total size: $(Format-Bytes $s.Bytes)"
    }

    # Events
    $btnBrowse.Add_Click({
        $d = New-Object System.Windows.Forms.FolderBrowserDialog
        $d.Description = "Select your iRacing paints folder"; $d.SelectedPath = $txtFolder.Text
        if ($d.ShowDialog() -eq "OK") { $txtFolder.Text = $d.SelectedPath; $txtLog.Clear(); Write-Log "Folder: $($txtFolder.Text)" ([System.Drawing.Color]::FromArgb(150,150,150)); Update-Stats $txtFolder.Text }
    })

    $btnScan.Add_Click({
        $f = $txtFolder.Text.Trim(); $txtLog.Clear()
        if (-not (Test-Path $f)) { Write-Log "ERROR: Folder not found: $f" ([System.Drawing.Color]::FromArgb(255,80,80)); return }
        Write-Log "Scanning: $f" ([System.Drawing.Color]::FromArgb(150,150,150))
        Update-Stats $f
        Write-Log "Scan complete." ([System.Drawing.Color]::FromArgb(150,150,150))
    })

    $btnClean.Add_Click({
        $folder = $txtFolder.Text.Trim()
        if (-not (Test-Path $folder)) {
            [System.Windows.Forms.MessageBox]::Show("Paints folder not found:`n$folder", "Folder Not Found", "OK", "Error") | Out-Null; return
        }
        $carFolders = Get-ChildItem -Path $folder -Directory
        if ($carFolders.Count -eq 0) { [System.Windows.Forms.MessageBox]::Show("No car folders found.", "Nothing to Clean", "OK", "Information") | Out-Null; return }

        $stats = Get-PaintStats $folder
        if ($stats.Files -eq 0) { [System.Windows.Forms.MessageBox]::Show("All folders are already empty.", "Already Clean", "OK", "Information") | Out-Null; return }

        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "Delete $($stats.Files) file(s) ($(Format-Bytes $stats.Bytes)) across $($carFolders.Count) car folder(s)?`n`nCar folders will be kept.",
            "Confirm Clean", "YesNo", "Warning")
        if ($confirm -ne "Yes") { return }

        $txtLog.Clear(); Write-Log "Cleaning..." ([System.Drawing.Color]::FromArgb(150,150,150))
        $btnClean.Enabled = $false; $btnClean.Text = "Cleaning..."; $form.Refresh()

        $totalFiles = 0; $totalBytes = 0
        foreach ($cf in $carFolders) {
            $files = Get-ChildItem -Path $cf.FullName -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer }
            $fc = $files.Count; $fb = ($files | Measure-Object -Property Length -Sum).Sum
            if ($fc -gt 0) {
                Remove-Item "$($cf.FullName)\*" -Recurse -Force -ErrorAction SilentlyContinue
                Write-Log "[OK]  $($cf.Name)  ($fc file(s), $(Format-Bytes $fb))" ([System.Drawing.Color]::FromArgb(80,200,120))
                $totalFiles += $fc; $totalBytes += if ($fb) { $fb } else { 0 }
            }
        }

        Write-Log ""; Write-Log "Done! Removed $totalFiles file(s), freed $(Format-Bytes $totalBytes)." ([System.Drawing.Color]::FromArgb(0,180,255))
        Update-Stats $folder
        $btnClean.Enabled = $true; $btnClean.Text = "Clean Paint Files"
    })

    $form.Add_Resize({
        $w = $form.ClientSize.Width - 32
        $txtFolder.Width = $w - 90; $btnBrowse.Left = $form.ClientSize.Width - 98
        $panelStats.Width = $w + 14; $txtLog.Width = $w + 14; $btnClean.Width = $w + 14
        $txtLog.Height = $form.ClientSize.Height - 234 - 62; $btnClean.Top = $form.ClientSize.Height - 62
    })

    $form.Add_Shown({
        if (Test-Path $script:DefaultPaints) {
            Write-Log "Ready. Scan to count files or click Clean to delete them." ([System.Drawing.Color]::FromArgb(150,150,150))
            Update-Stats $script:DefaultPaints
        } else {
            Write-Log "WARNING: Default paints folder not found. Use Browse to locate it." ([System.Drawing.Color]::FromArgb(255,200,0))
        }
    })

    [System.Windows.Forms.Application]::Run($form)
}

# =============================================================================
# STARTUP
# =============================================================================

$status = Test-License

switch ($status.Status) {
    "OK" {
        Show-MainForm $status
    }
    "Grace" {
        Show-MainForm $status
    }
    "Invalid" {
        $msg = if ($status.Message) { $status.Message } else { "Your license is no longer active." }
        Show-ActivationForm $msg | Out-Null
        if (Load-License) { Show-MainForm (Test-License) }
    }
    "GraceExpired" {
        Show-ActivationForm "Offline grace period expired. Please reconnect to the internet and re-enter your key." | Out-Null
        if (Load-License) { Show-MainForm (Test-License) }
    }
    default {
        # NoLicense
        $activated = Show-ActivationForm ""
        if ($activated) { Show-MainForm (Test-License) }
    }
}
