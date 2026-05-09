# ==============================================================================
# HBUK USER DEPLOYMENT SUITE V4.5
# ==============================================================================

# --- ADMIN PRIVILEGE CHECK ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $proc = New-Object System.Diagnostics.ProcessStartInfo "powershell"
    $proc.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`""
    $proc.Verb = "runas"
    try { [System.Diagnostics.Process]::Start($proc) | Out-Null } catch {}
    Exit
}

# --- FIX $PSScriptRoot FOR COMPILED EXE ---
$env:HBUK_BASE_DIR = $PSScriptRoot
if (-not $env:HBUK_BASE_DIR) { $env:HBUK_BASE_DIR = Split-Path -Parent ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }

# --- INIT WINFORMS ---
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic
[System.Windows.Forms.Application]::EnableVisualStyles()

# --- FORM SETUP ---

$form = New-Object System.Windows.Forms.Form
$form.Text = "HBUK User Deployment Suite V4.5"
$form.Size = New-Object System.Drawing.Size(1050, 750)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.BackColor = [System.Drawing.Color]::FromName("White")
$iconPath = Join-Path $env:HBUK_BASE_DIR "packages\icons\upm_logo.ico"
if (Test-Path $iconPath) { $form.Icon = New-Object System.Drawing.Icon($iconPath) }

# --- LOGGING ---
$script:LogFolder = Join-Path $env:HBUK_BASE_DIR "logs"
if (-not (Test-Path $script:LogFolder)) { New-Item -ItemType Directory -Path $script:LogFolder -Force | Out-Null }
$script:LogFile = Join-Path $script:LogFolder "GUI-$env:COMPUTERNAME-$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"

function Write-Log($msg) {
    $ts = Get-Date -Format "HH:mm:ss"
    $line = "[$ts] $msg"
    try { Add-Content -Path $script:LogFile -Value $line -ErrorAction SilentlyContinue } catch {}
    if ($script:rtbLog) {
        $script:rtbLog.AppendText("$line`n")
        $script:rtbLog.ScrollToCaret()
        [System.Windows.Forms.Application]::DoEvents()
    }
}

# --- ACCENT COLOR (dari config atau default) ---
# Fail konfigurasi: packages/config/accent_color.txt (satu baris hex, cth: #1ABC9C)
$script:AccentColor = [System.Drawing.Color]::FromArgb(27, 174, 112)
$accentCfg = Join-Path $env:HBUK_BASE_DIR "packages\config\accent_color.txt"
if (Test-Path $accentCfg) {
    $hexVal = (Get-Content $accentCfg -First 1).Trim()
    if ($hexVal -match '^#?([0-9A-Fa-f]{6})$') {
        $h = $matches[1]
        $script:AccentColor = [System.Drawing.Color]::FromArgb(
            [Convert]::ToInt32($h.Substring(0,2),16),
            [Convert]::ToInt32($h.Substring(2,2),16),
            [Convert]::ToInt32($h.Substring(4,2),16))
    }
}

# --- DARK / LIGHT MODE (F-10) ---
$script:IsDarkMode = $false
function Set-UITheme {
    if ($script:IsDarkMode) {
        $bgMain = [System.Drawing.Color]::FromArgb(30, 30, 30)
        $bgPanel = [System.Drawing.Color]::FromArgb(40, 40, 40)
        $fgText = [System.Drawing.Color]::White
        $bgBtn = [System.Drawing.Color]::FromArgb(55, 55, 55)
        $fgBtn = [System.Drawing.Color]::White
        $bgLog = [System.Drawing.Color]::FromArgb(20, 20, 20)
        $fgLog = [System.Drawing.Color]::LimeGreen
    } else {
        $bgMain = [System.Drawing.Color]::White
        $bgPanel = [System.Drawing.Color]::White
        $fgText = [System.Drawing.Color]::Black
        $bgBtn = [System.Drawing.Color]::FromArgb(240, 240, 240)
        $fgBtn = [System.Drawing.Color]::Black
        $bgLog = [System.Drawing.Color]::FromArgb(30, 30, 30)
        $fgLog = [System.Drawing.Color]::LimeGreen
    }
    $form.BackColor = $bgMain
    $panelContent.BackColor = $bgPanel
    $lblLogTitle.ForeColor = $fgText
    $script:rtbLog.BackColor = $bgLog
    $script:rtbLog.ForeColor = $fgLog
    # Rekursif kemaskini semua panel dan kawalan
    foreach ($panel in @($panelMainMenu, $panelSPAI, $panelRustDesk, $panelUser)) {
        if ($panel) {
            $panel.BackColor = $bgPanel
            foreach ($ctrl in $panel.Controls) {
                if ($ctrl -is [System.Windows.Forms.Button]) { $ctrl.BackColor = $bgBtn; $ctrl.ForeColor = $fgBtn }
                elseif ($ctrl -is [System.Windows.Forms.Label]) { $ctrl.ForeColor = $fgText }
                elseif ($ctrl -is [System.Windows.Forms.Panel]) {
                    $ctrl.BackColor = $bgPanel
                    foreach ($subCtrl in $ctrl.Controls) {
                        if ($subCtrl -is [System.Windows.Forms.Button]) { $subCtrl.BackColor = $bgBtn; $subCtrl.ForeColor = $fgBtn }
                        elseif ($subCtrl -is [System.Windows.Forms.Label]) { $subCtrl.ForeColor = $fgText }
                    }
                }
            }
        }
    }
    # Butang tema khas (SPAI hijau) kekalkan warna asal
    if ($btnPasangSPAI) { $btnPasangSPAI.BackColor = [System.Drawing.Color]::FromArgb(27, 174, 112); $btnPasangSPAI.ForeColor = [System.Drawing.Color]::White }
    if ($btnManPasangSPAI) { $btnManPasangSPAI.BackColor = [System.Drawing.Color]::FromArgb(27, 174, 112); $btnManPasangSPAI.ForeColor = [System.Drawing.Color]::White }
}

# --- ANIMATED TOAST NOTIFICATION ---
# Popup notifikasi berjaya dengan animasi fade-in/out
function Show-ToastNotification($message, $title, $durationMs) {
    if (-not $durationMs) { $durationMs = 2500 }
    $toast = New-Object System.Windows.Forms.Form
    $toast.FormBorderStyle = 'None'
    $toast.StartPosition = 'Manual'
    $toast.Size = New-Object System.Drawing.Size(380, 90)
    $toast.BackColor = $script:AccentColor
    $toast.TopMost = $true
    $toast.ShowInTaskbar = $false
    $toast.Opacity = 0
    # Letak di bawah kanan skrin
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $toast.Location = New-Object System.Drawing.Point(($screen.Right - 395), ($screen.Bottom - 105))
    # Ikon tanda semak
    $lblIcon = New-Object System.Windows.Forms.Label
    $lblIcon.Text = [char]0x2714
    $lblIcon.Font = New-Object System.Drawing.Font('Segoe UI', 24)
    $lblIcon.ForeColor = [System.Drawing.Color]::White
    $lblIcon.Location = New-Object System.Drawing.Point(12, 18)
    $lblIcon.AutoSize = $true
    $toast.Controls.Add($lblIcon)
    # Tajuk
    $lblT = New-Object System.Windows.Forms.Label
    $lblT.Text = $title
    $lblT.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
    $lblT.ForeColor = [System.Drawing.Color]::White
    $lblT.Location = New-Object System.Drawing.Point(55, 12)
    $lblT.AutoSize = $true
    $toast.Controls.Add($lblT)
    # Mesej
    $lblM = New-Object System.Windows.Forms.Label
    $lblM.Text = $message
    $lblM.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $lblM.ForeColor = [System.Drawing.Color]::White
    $lblM.Location = New-Object System.Drawing.Point(55, 38)
    $lblM.MaximumSize = New-Object System.Drawing.Size(310, 45)
    $lblM.AutoSize = $true
    $toast.Controls.Add($lblM)
    $toast.Show()
    # Animasi fade-in
    for ($i = 0; $i -le 10; $i++) { $toast.Opacity = $i / 10; Start-Sleep -Milliseconds 30; [System.Windows.Forms.Application]::DoEvents() }
    # Tahan paparan
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt $durationMs) { Start-Sleep -Milliseconds 50; [System.Windows.Forms.Application]::DoEvents() }
    # Animasi fade-out
    for ($i = 10; $i -ge 0; $i--) { $toast.Opacity = $i / 10; Start-Sleep -Milliseconds 30; [System.Windows.Forms.Application]::DoEvents() }
    $toast.Close(); $toast.Dispose()
}

# --- LEFT INFO PANEL (PERMANENT) ---
$panelLeft = New-Object System.Windows.Forms.Panel
$panelLeft.Size = New-Object System.Drawing.Size(320, 750)
$panelLeft.Location = New-Object System.Drawing.Point(0, 0)
$panelLeft.BackColor = [System.Drawing.Color]::FromArgb(44, 62, 80)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = "HBUK USER`nDEPLOYMENT SUITE"
$lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
$lblTitle.ForeColor = [System.Drawing.Color]::White
$lblTitle.AutoSize = $false
$lblTitle.Size = New-Object System.Drawing.Size(320, 55)
$lblTitle.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$lblTitle.Location = New-Object System.Drawing.Point(0, 8)
$panelLeft.Controls.Add($lblTitle)

# --- LOGO ---
# Format logo yang disokong: PNG (disyorkan, min 256x256px) atau ICO (multi-resolusi)
# Letakkan fail sebagai packages/icons/upm_logo.png untuk kualiti terbaik
# Fallback: packages/icons/upm_logo.ico
$picLogo = New-Object System.Windows.Forms.PictureBox
$picLogo.Location = New-Object System.Drawing.Point(120, 65)
$picLogo.Size = New-Object System.Drawing.Size(80, 80)
$picLogo.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
$picLogo.BackColor = [System.Drawing.Color]::Transparent
# Keutamaan: PNG > ICO (PNG memberikan kualiti lebih baik tanpa pixelation)
$logoPng = Join-Path $env:HBUK_BASE_DIR "packages\icons\upm_logo.png"
$logoIco = Join-Path $env:HBUK_BASE_DIR "packages\icons\upm_logo.ico"
if (Test-Path $logoPng) {
    try {
        $srcImg = [System.Drawing.Image]::FromFile($logoPng)
        $bmp = New-Object System.Drawing.Bitmap(80, 80)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g.DrawImage($srcImg, 0, 0, 80, 80)
        $g.Dispose()
        $picLogo.Image = $bmp
    } catch { try { $picLogo.Image = [System.Drawing.Image]::FromFile($logoPng) } catch {} }
}
elseif (Test-Path $logoIco) {
    try {
        $ico = New-Object System.Drawing.Icon($logoIco, 256, 256)
        $srcBmp = $ico.ToBitmap()
        $bmp = New-Object System.Drawing.Bitmap(80, 80)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $g.DrawImage($srcBmp, 0, 0, 80, 80)
        $g.Dispose()
        $picLogo.Image = $bmp
    } catch { try { $picLogo.Image = [System.Drawing.Image]::FromFile($logoIco) } catch {} }
}
$panelLeft.Controls.Add($picLogo)

$rtbInfo = New-Object System.Windows.Forms.RichTextBox
$rtbInfo.Size = New-Object System.Drawing.Size(280, 485)
$rtbInfo.Location = New-Object System.Drawing.Point(20, 155)
$rtbInfo.Font = New-Object System.Drawing.Font("Consolas", 9)
$rtbInfo.ReadOnly = $true
$rtbInfo.BackColor = [System.Drawing.Color]::FromArgb(44, 62, 80)
$rtbInfo.ForeColor = [System.Drawing.Color]::White
$rtbInfo.BorderStyle = 0
$panelLeft.Controls.Add($rtbInfo)

# Function to fetch live data (enhanced)
function Update-SystemInfo {
    Write-Log "DEBUG BaseDir: $env:HBUK_BASE_DIR"
    $os = (Get-CimInstance Win32_OperatingSystem).Caption
    $ramRound = [Math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
    
    # SPAI Status
    $spaiStatus = "Tidak Dipasang"
    $spaiTag = "N/A"
    $svcSpai = Get-Service glpi-agent -ErrorAction SilentlyContinue
    if ($svcSpai) {
        $spaiStatus = "Dipasang ($($svcSpai.Status))"
        $tagVal = (Get-ItemProperty "HKLM:\SOFTWARE\GLPI-Agent" -Name tag -ErrorAction SilentlyContinue).tag
        if ($tagVal) { $spaiTag = $tagVal }
    }
    
    # RustDesk Status
    $rdStatus = "Tidak Dipasang"; $rdVer = "N/A"; $rdId = "N/A"; $rdIp = "N/A"
    $rdExe = ""
    if (Test-Path "$env:ProgramFiles\RustDesk\rustdesk.exe") {
        $rdExe = "$env:ProgramFiles\RustDesk\rustdesk.exe"
        $rdStatus = "Dipasang (x64)"
    }
    elseif (Test-Path "${env:ProgramFiles(x86)}\RustDesk\rustdesk.exe") {
        $rdExe = "${env:ProgramFiles(x86)}\RustDesk\rustdesk.exe"
        $rdStatus = "Dipasang (x86)"
    }
    if ($rdExe) {
        try { 
            $rdVer = (Get-Item $rdExe).VersionInfo.FileVersion
            if ($rdVer -match '\+') { $rdVer = $rdVer.Split('+')[0] }
        }
        catch {}
        try {
            $job = Start-Job -ScriptBlock { param($exe) & $exe --get-id 2>$null } -ArgumentList $rdExe
            $completed = $job | Wait-Job -Timeout 5
            if ($completed) {
                $rdIdRaw = Receive-Job $job
                if ($rdIdRaw) { $rdId = ($rdIdRaw | Out-String).Trim() }
            } else { Write-Log "AMARAN: --get-id timeout (5s)." }
            Remove-Job $job -Force -ErrorAction SilentlyContinue
        }
        catch {}

        # Fallback to reading TOML directly if --get-id is empty or fails
        if (-not $rdId -or $rdId -eq "N/A" -or $rdId -eq "") {
            $idFile = "C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\RustDesk\config\HBUK_ID.txt"
            if (Test-Path $idFile) { $rdId = (Get-Content $idFile -Raw).Trim() }
            
            if (-not $rdId) {
                $toml1 = "C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\RustDesk\config\RustDesk.toml"
                if (Test-Path $toml1) {
                    foreach ($line in Get-Content $toml1 -ErrorAction SilentlyContinue) {
                        if ($line -match "^id\s*=\s*'(.*)'") { $rdId = $matches[1]; break }
                        elseif ($line -match "^enc_id\s*=\s*'(.*)'") { $rdId = "<Encrypted ID>" } # fallback if no plaintext file
                    }
                }
            }
        }

        $tomlPath = "C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\RustDesk\config\RustDesk2.toml"
        if (Test-Path $tomlPath) {
            foreach ($line in Get-Content $tomlPath -ErrorAction SilentlyContinue) {
                if ($line -match "custom-rendezvous-server\s*=\s*'(.*)'") { $rdIp = $matches[1]; break }
            }
        }
    }
    
    # Local MSI versions available (Using .NET to bypass PowerShell OneDrive elevation bug)
    $rdFiles = try { [System.IO.Directory]::GetFiles("$env:HBUK_BASE_DIR\packages\installer", "rustdesk-*.msi") } catch { @() }
    $localRdMsi = if ($rdFiles.Count -gt 0) { New-Object System.IO.FileInfo ($rdFiles | Sort-Object | Select-Object -Last 1) } else { $null }
    $spaiFiles = try { [System.IO.Directory]::GetFiles("$env:HBUK_BASE_DIR\packages\installer", "GLPI-Agent-*.msi") } catch { @() }
    $localSpaiMsi = if ($spaiFiles.Count -gt 0) { New-Object System.IO.FileInfo ($spaiFiles | Sort-Object | Select-Object -Last 1) } else { $null }
    $rdMsiVer = if ($localRdMsi -and ([System.IO.Path]::GetFileName($localRdMsi.FullName)) -match "(\d+\.\d+\.\d+)") { $matches[1] } else { "Tiada" }
    $spaiMsiVer = if ($localSpaiMsi -and ([System.IO.Path]::GetFileName($localSpaiMsi.FullName)) -match "(\d+\.\d+)") { $matches[1] } else { "Tiada" }
    
    # Perbandingan versi dipasang vs MSI tersedia (F-06)
    $rdVerCompare = ""
    if ($rdVer -ne "N/A" -and $rdMsiVer -ne "Tiada") {
        try {
            if ([version]$rdMsiVer -gt [version]$rdVer) { $rdVerCompare = " [KEMASKINI TERSEDIA]" }
            elseif ([version]$rdMsiVer -eq [version]$rdVer) { $rdVerCompare = " [TERKINI]" }
        } catch {}
    }

    $rtbInfo.Text = "MAKLUMAT SISTEM`n" +
    "------------------------`n" +
    "HOSTNAME:`n  $env:COMPUTERNAME`n`n" +
    "OS:`n  $os`n`n" +
    "RAM: $ramRound GB`n`n" +
    "--- SPAI AGENT ---`n" +
    "Status : $spaiStatus`n" +
    "Tag    : $spaiTag`n`n" +
    "--- RUSTDESK ---`n" +
    "Status : $rdStatus`n" +
    "Versi  : $rdVer$rdVerCompare`n" +
    "ID     : $rdId`n" +
    "Server : $rdIp`n`n" +
    "--- PAKEJ OFFLINE ---`n" +
    "RustDesk MSI : $rdMsiVer`n" +
    "SPAI MSI     : $spaiMsiVer"
}

$btnRefreshInfo = New-Object System.Windows.Forms.Button
$btnRefreshInfo.Text = "Refresh Parameter"
$btnRefreshInfo.Location = New-Object System.Drawing.Point(20, 650)
$btnRefreshInfo.Size = New-Object System.Drawing.Size(280, 40)
$btnRefreshInfo.FlatStyle = "Flat"
$btnRefreshInfo.ForeColor = [System.Drawing.Color]::White
$btnRefreshInfo.Add_Click({ Update-SystemInfo })
$panelLeft.Controls.Add($btnRefreshInfo)

# --- BUTANG TEMA GELAP/TERANG (F-10) ---
$btnThemeToggle = New-Object System.Windows.Forms.Button
$btnThemeToggle.Text = [char]0x263D + " Dark Mode"
$btnThemeToggle.Location = New-Object System.Drawing.Point(20, 695)
$btnThemeToggle.Size = New-Object System.Drawing.Size(280, 30)
$btnThemeToggle.FlatStyle = "Flat"
$btnThemeToggle.ForeColor = [System.Drawing.Color]::White
$btnThemeToggle.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$btnThemeToggle.Add_Click({
    $script:IsDarkMode = -not $script:IsDarkMode
    if ($script:IsDarkMode) { $btnThemeToggle.Text = [char]0x2600 + " Light Mode" }
    else { $btnThemeToggle.Text = [char]0x263D + " Dark Mode" }
    Set-UITheme
})
$panelLeft.Controls.Add($btnThemeToggle)

# --- AUTO-REFRESH TIMER (F-13) ---
# Refresh maklumat sistem setiap 60 saat secara automatik
$script:autoRefreshTimer = New-Object System.Windows.Forms.Timer
$script:autoRefreshTimer.Interval = 60000
$script:autoRefreshTimer.Add_Tick({ Update-SystemInfo })
$script:autoRefreshTimer.Start()

$form.Controls.Add($panelLeft)

# --- RIGHT CONTENT PANEL (top: panels, bottom: status log) ---
$panelContent = New-Object System.Windows.Forms.Panel
$panelContent.Size = New-Object System.Drawing.Size(710, 500)
$panelContent.Location = New-Object System.Drawing.Point(320, 0)
$panelContent.BackColor = [System.Drawing.Color]::White
$form.Controls.Add($panelContent)

# --- STATUS LOG PANEL (bottom right, always visible) ---
$lblLogTitle = New-Object System.Windows.Forms.Label
$lblLogTitle.Text = "STATUS LOG"
$lblLogTitle.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$lblLogTitle.Location = New-Object System.Drawing.Point(325, 505)
$lblLogTitle.AutoSize = $true
$form.Controls.Add($lblLogTitle)

$script:rtbLog = New-Object System.Windows.Forms.RichTextBox
$script:rtbLog.Size = New-Object System.Drawing.Size(700, 180)
$script:rtbLog.Location = New-Object System.Drawing.Point(325, 525)
$script:rtbLog.Font = New-Object System.Drawing.Font("Consolas", 9)
$script:rtbLog.ReadOnly = $true
$script:rtbLog.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$script:rtbLog.ForeColor = [System.Drawing.Color]::LimeGreen
$script:rtbLog.BorderStyle = 0
$form.Controls.Add($script:rtbLog)

function Show-Panel($panelToShow) {
    $panelMainMenu.Visible = $false
    $panelSPAI.Visible = $false
    $panelRustDesk.Visible = $false
    $panelUser.Visible = $false
    $panelToShow.Visible = $true
    # Reset SPAI sub-panels to menu when entering SPAI
    if ($panelToShow -eq $panelSPAI) {
        $panelSPAIMenu.Visible = $true
        $panelSPAIAuto.Visible = $false
        $panelSPAIManual.Visible = $false
    }
}

# -------------------------------------------------------------
# PANEL 1: MAIN MENU
# -------------------------------------------------------------
$panelMainMenu = New-Object System.Windows.Forms.Panel
$panelMainMenu.Size = $panelContent.Size
$panelMainMenu.Location = New-Object System.Drawing.Point(0, 0)

$lblMainMenu = New-Object System.Windows.Forms.Label
$lblMainMenu.Text = "[SILA PILIH TINDAKAN]"
$lblMainMenu.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
$lblMainMenu.Location = New-Object System.Drawing.Point(30, 30)
$lblMainMenu.AutoSize = $true
$panelMainMenu.Controls.Add($lblMainMenu)

function New-MainMenuButton($text, $y) {
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $text
    $btn.Location = New-Object System.Drawing.Point(30, $y)
    $btn.Size = New-Object System.Drawing.Size(550, 40)
    $btn.Font = New-Object System.Drawing.Font("Segoe UI", 11)
    $btn.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $panelMainMenu.Controls.Add($btn)
    return $btn
}

$btnMenu1 = New-MainMenuButton "1. Pengurusan Pengguna" 80
$btnMenu1.Add_Click({ Show-Panel $panelUser })

$btnMenu2 = New-MainMenuButton "2. Pengurusan RustDesk" 130
$btnMenu2.Add_Click({ Show-Panel $panelRustDesk })

$btnMenu3 = New-MainMenuButton "3. Pengurusan SPAI" 180
$btnMenu3.Add_Click({ Show-Panel $panelSPAI })

$btnMenu4 = New-MainMenuButton "4. Pasang Tema Windows HBUK" 230
$btnMenu4.Add_Click({
        Write-Log "--- Pemasangan Tema HBUK ---"
        $themeDir = "$env:HBUK_BASE_DIR\packages\themes"
        # Semakan awal: pastikan folder tema wujud dan ada fail (B-05)
        if (-not (Test-Path $themeDir)) {
            Write-Log "RALAT: Folder packages\themes\ tidak wujud."
            [System.Windows.Forms.MessageBox]::Show("Folder 'packages\themes' tidak dijumpai.", "Ralat", 0, 48); return
        }
        $dark = Join-Path $themeDir "HBUK_THEME_DARK.deskthemepack"
        $light = Join-Path $themeDir "HBUK_THEME_LIGHT.deskthemepack"
        $hasDark = Test-Path $dark; $hasLight = Test-Path $light
    
        if (-not $hasDark -and -not $hasLight) {
            Write-Log "RALAT: Tiada fail tema dijumpai di packages\themes\"
            [System.Windows.Forms.MessageBox]::Show("Tiada fail .deskthemepack dijumpai di folder themes.`nLetakkan fail HBUK_THEME_DARK.deskthemepack atau HBUK_THEME_LIGHT.deskthemepack.", "Ralat", 0, 48); return
        }
    
        $msg = "Pilih tema:`n"
        if ($hasDark) { $msg += "`n[1] HBUK Dark Theme" }
        if ($hasLight) { $msg += "`n[2] HBUK Light Theme" }
        $choice = [Microsoft.VisualBasic.Interaction]::InputBox($msg, "Pasang Tema HBUK", "1")
    
        if ($choice -eq "1" -and $hasDark) {
            Write-Log "Memasang HBUK Dark Theme..."
            Start-Process explorer.exe -ArgumentList "`"$dark`""; Write-Log "[OK] Tema Dark diaplikasikan."
        }
        elseif ($choice -eq "2" -and $hasLight) {
            Write-Log "Memasang HBUK Light Theme..."
            Start-Process explorer.exe -ArgumentList "`"$light`""; Write-Log "[OK] Tema Light diaplikasikan."
        }
    })

$btnMenu5 = New-MainMenuButton "5. Housekeeping" 280
$btnMenu5.Add_Click({
        Write-Log "--- Housekeeping ---"
        # Pilihan housekeeping
        $hkMsg = "Pilih tindakan housekeeping:`n`n[1] Bersih TEMP sahaja (pantas)`n[2] Bersih penuh (TEMP + Cache Browser + WinUpdate + Recycle Bin + DNS)`n`nMasukkan pilihan (1/2):"
        $hkChoice = [Microsoft.VisualBasic.Interaction]::InputBox($hkMsg, "Housekeeping", "1")
        if (-not $hkChoice) { return }
        $totalCleaned = 0
        # TEMP sentiasa dibersihkan
        $count1 = (Get-ChildItem "$env:TEMP\*" -Recurse -ErrorAction SilentlyContinue).Count
        Remove-Item "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item "${env:SystemRoot}\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
        $totalCleaned += $count1
        Write-Log "[OK] TEMP dibersihkan (~$count1 fail)."
        if ($hkChoice -eq "2") {
            # Cache browser (Edge/Chrome)
            $browserPaths = @(
                "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache",
                "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache"
            )
            foreach ($bp in $browserPaths) {
                if (Test-Path $bp) {
                    $bc = (Get-ChildItem "$bp\*" -Recurse -ErrorAction SilentlyContinue).Count
                    Remove-Item "$bp\*" -Recurse -Force -ErrorAction SilentlyContinue
                    $totalCleaned += $bc
                    Write-Log "[OK] Cache browser dibersihkan: $bp (~$bc fail)"
                }
            }
            # Windows Update cache
            $wuPath = "$env:SystemRoot\SoftwareDistribution\Download"
            if (Test-Path $wuPath) {
                $wc = (Get-ChildItem "$wuPath\*" -Recurse -ErrorAction SilentlyContinue).Count
                Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
                Remove-Item "$wuPath\*" -Recurse -Force -ErrorAction SilentlyContinue
                Start-Service wuauserv -ErrorAction SilentlyContinue
                $totalCleaned += $wc
                Write-Log "[OK] Windows Update cache dibersihkan (~$wc fail)."
            }
            # Recycle Bin
            try { Clear-RecycleBin -Force -ErrorAction SilentlyContinue; Write-Log "[OK] Recycle Bin dikosongkan." } catch {}
            # Flush DNS
            ipconfig /flushdns 2>$null | Out-Null
            Write-Log "[OK] DNS cache dibersihkan."
        }
        Write-Log "[OK] Housekeeping selesai. Jumlah: ~$totalCleaned fail dibersihkan."
        [System.Windows.Forms.MessageBox]::Show("Housekeeping Selesai!`nJumlah ~$totalCleaned fail dibersihkan.", "Berjaya", 0, 64)
    })

$btnMenu6 = New-MainMenuButton "6. Tentang / About" 330
$btnMenu6.Add_Click({
        # Dialog About (F-12)
        $aboutDlg = New-Object System.Windows.Forms.Form
        $aboutDlg.Text = "Tentang HBUK Suite"
        $aboutDlg.Size = New-Object System.Drawing.Size(420, 300)
        $aboutDlg.StartPosition = "CenterParent"
        $aboutDlg.FormBorderStyle = "FixedDialog"
        $aboutDlg.MaximizeBox = $false; $aboutDlg.MinimizeBox = $false
        $aboutDlg.BackColor = [System.Drawing.Color]::FromArgb(44, 62, 80)
        $lblAboutTitle = New-Object System.Windows.Forms.Label
        $lblAboutTitle.Text = "HBUK USER DEPLOYMENT SUITE"
        $lblAboutTitle.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
        $lblAboutTitle.ForeColor = [System.Drawing.Color]::White
        $lblAboutTitle.Location = New-Object System.Drawing.Point(30, 25)
        $lblAboutTitle.AutoSize = $true
        $aboutDlg.Controls.Add($lblAboutTitle)
        $lblAboutInfo = New-Object System.Windows.Forms.Label
        $lblAboutInfo.Text = "Versi: V4.5`nTarikh Bina: $(Get-Date -Format 'yyyy-MM-dd')`n`nUnit Pengurusan Maklumat (UPM)`nHospital Bahagia Ulu Kinta`nJKN Perak, KKM`n`nDibangunkan untuk pengurusan deployment`nkomputer hospital secara portable."
        $lblAboutInfo.Font = New-Object System.Drawing.Font("Segoe UI", 10)
        $lblAboutInfo.ForeColor = [System.Drawing.Color]::White
        $lblAboutInfo.Location = New-Object System.Drawing.Point(30, 60)
        $lblAboutInfo.AutoSize = $true
        $aboutDlg.Controls.Add($lblAboutInfo)
        $btnAboutOk = New-Object System.Windows.Forms.Button
        $btnAboutOk.Text = "Tutup"
        $btnAboutOk.Location = New-Object System.Drawing.Point(150, 225)
        $btnAboutOk.Size = New-Object System.Drawing.Size(120, 30)
        $btnAboutOk.FlatStyle = "Flat"
        $btnAboutOk.ForeColor = [System.Drawing.Color]::White
        $btnAboutOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $aboutDlg.Controls.Add($btnAboutOk)
        $aboutDlg.ShowDialog() | Out-Null
    })

$btnMenu7 = New-MainMenuButton "7. Keluar" 380
$btnMenu7.Add_Click({ $form.Close() })


# -------------------------------------------------------------
# PANEL 2: PENGURUSAN SPAI (Sub-Menu)
# -------------------------------------------------------------
$panelSPAI = New-Object System.Windows.Forms.Panel
$panelSPAI.Size = $panelContent.Size
$panelSPAI.Location = New-Object System.Drawing.Point(0, 0)
$panelSPAI.Visible = $false

$lblSPAITitle = New-Object System.Windows.Forms.Label
$lblSPAITitle.Text = "PENGURUSAN SPAI"
$lblSPAITitle.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
$lblSPAITitle.Location = New-Object System.Drawing.Point(30, 20)
$lblSPAITitle.AutoSize = $true
$panelSPAI.Controls.Add($lblSPAITitle)

# --- SPAI Sub-panels ---
$panelSPAIMenu = New-Object System.Windows.Forms.Panel
$panelSPAIMenu.Size = New-Object System.Drawing.Size(680, 450)
$panelSPAIMenu.Location = New-Object System.Drawing.Point(0, 55)
$panelSPAI.Controls.Add($panelSPAIMenu)

$panelSPAIAuto = New-Object System.Windows.Forms.Panel
$panelSPAIAuto.Size = New-Object System.Drawing.Size(680, 450)
$panelSPAIAuto.Location = New-Object System.Drawing.Point(0, 55)
$panelSPAIAuto.Visible = $false
$panelSPAI.Controls.Add($panelSPAIAuto)

$panelSPAIManual = New-Object System.Windows.Forms.Panel
$panelSPAIManual.Size = New-Object System.Drawing.Size(680, 450)
$panelSPAIManual.Location = New-Object System.Drawing.Point(0, 55)
$panelSPAIManual.Visible = $false
$panelSPAI.Controls.Add($panelSPAIManual)

function Show-SPAIPanel($p) {
    $panelSPAIMenu.Visible = $false
    $panelSPAIAuto.Visible = $false
    $panelSPAIManual.Visible = $false
    $p.Visible = $true
}

# --- SPAI Sub-Menu Buttons ---
function New-SPAIMenuBtn($text, $y) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text
    $b.Location = New-Object System.Drawing.Point(30, $y)
    $b.Size = New-Object System.Drawing.Size(600, 45)
    $b.Font = New-Object System.Drawing.Font("Segoe UI", 11)
    $b.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $panelSPAIMenu.Controls.Add($b)
    return $b
}

$btnSPAI1 = New-SPAIMenuBtn "1. Tetapan SPAI (Pilihan Dropdown)" 20
$btnSPAI1.Add_Click({ Show-SPAIPanel $panelSPAIAuto })

$btnSPAI2 = New-SPAIMenuBtn "2. Tetapan SPAI Manual" 75
$btnSPAI2.Add_Click({ Show-SPAIPanel $panelSPAIManual })

$btnSPAI3 = New-SPAIMenuBtn "3. Nyahpasang SPAI Agent" 130
$btnSPAI3.Add_Click({
    Write-Log "--- Nyahpasang SPAI Agent ---"
    $unKeys = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*GLPI*Agent*" }
    if ($unKeys) {
        $entry = $unKeys | Select-Object -First 1
        $guid = $entry.PSChildName
        Write-Log "Dijumpai: $($entry.DisplayName). GUID: $guid"
        $proc = Start-Process "msiexec.exe" -ArgumentList "/x $guid /qn /norestart" -Wait -PassThru
        Write-Log "[OK] SPAI Agent dinyahpasang. Exit code: $($proc.ExitCode)"
        [System.Windows.Forms.MessageBox]::Show("SPAI Agent telah dinyahpasang.", "Berjaya", 0, 64)
    } else {
        Write-Log "SPAI Agent tidak ditemui dalam Registry."
        [System.Windows.Forms.MessageBox]::Show("SPAI Agent tidak ditemui dalam sistem.", "Makluman", 0, 64)
    }
    Update-SystemInfo
})

$btnSPAIBack = New-Object System.Windows.Forms.Button
$btnSPAIBack.Text = "< Kembali ke Menu SPAI"
$btnSPAIBack.Location = New-Object System.Drawing.Point(430, 0)
$btnSPAIBack.Size = New-Object System.Drawing.Size(230, 35)
$btnSPAIBack.Add_Click({ Show-SPAIPanel $panelSPAIMenu })
$panelSPAIAuto.Controls.Add($btnSPAIBack)

$btnSPAIBackM = New-Object System.Windows.Forms.Button
$btnSPAIBackM.Text = "< Kembali ke Menu SPAI"
$btnSPAIBackM.Location = New-Object System.Drawing.Point(430, 0)
$btnSPAIBackM.Size = New-Object System.Drawing.Size(230, 35)
$btnSPAIBackM.Add_Click({ Show-SPAIPanel $panelSPAIMenu })
$panelSPAIManual.Controls.Add($btnSPAIBackM)

# --- VC++ Auto-Install Helper ---
function Install-VCRedistIfNeeded {
    $vcCheck = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*","HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" -EA SilentlyContinue | Where-Object { $_.DisplayName -like "*Visual C++*" -and $_.DisplayName -like "*x64*" -and $_.DisplayName -like "*Redistributable*" }
    if (-not $vcCheck) {
        Write-Log "VC++ Redistributable tidak dijumpai. Memasang secara automatik..."
        $vcPath = Get-ChildItem "$env:HBUK_BASE_DIR\packages\tools\VC_redist.x64.exe" -EA SilentlyContinue
        if ($vcPath) {
            $proc = Start-Process -FilePath $vcPath.FullName -ArgumentList "/install /quiet /norestart" -Wait -PassThru
            Write-Log "[OK] VC++ dipasang automatik. Exit: $($proc.ExitCode)"
        } else {
            Write-Log "AMARAN: VC_redist.x64.exe tidak dijumpai di packages\tools\"
        }
    } else {
        Write-Log "VC++ Redistributable sudah dipasang."
    }
}

# --- SPAI Install Logic (shared) ---
# Server URL diambil dari packages/config/spai_config.txt (format: SERVER=url)
# Fallback: hardcoded default jika fail tidak dijumpai
function Install-SPAIWithTag($finalTag) {
    $serverUrl = "http://10.138.101.145,https://helpdeskict.moh.gov.my/"
    $spaiCfg = Join-Path $env:HBUK_BASE_DIR "packages\config\spai_config.txt"
    if (Test-Path $spaiCfg) {
        foreach ($cfgLine in Get-Content $spaiCfg) {
            if ($cfgLine -match "^SERVER=(.*)") { $serverUrl = $matches[1].Trim() }
        }
        Write-Log "SPAI server URL dari config: $serverUrl"
    } else {
        Write-Log "AMARAN: spai_config.txt tidak dijumpai. Guna URL lalai."
    }
    Write-Log "--- MULA: Pemasangan SPAI Agent ---"
    Write-Log "Tag: $finalTag"
    # Auto-install VC++ if needed
    Install-VCRedistIfNeeded
    # Install SPAI
    $spaiFiles = try { [System.IO.Directory]::GetFiles("$env:HBUK_BASE_DIR\packages\installer", "GLPI-Agent-*.msi") } catch { @() }
    $localMsi = if ($spaiFiles.Count -gt 0) { New-Object System.IO.FileInfo ($spaiFiles | Sort-Object | Select-Object -Last 1) } else { $null }
    if ($localMsi) {
        Write-Log "MSI lokal dijumpai: $($localMsi.Name)"
        Write-Log "Memasang via msiexec... Sila tunggu."
        $logPath = Join-Path $script:LogFolder "SPAI-Install-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
        $msiArgs = "/i `"$($localMsi.FullName)`" SERVER=`"$serverUrl`" RUNNOW=1 ADDLOCAL=ALL EXECMODE=Service INSTALLSERVICE=1 /qn /norestart /L*v `"$logPath`""
        $proc = Start-Process "msiexec.exe" -ArgumentList $msiArgs -Wait -PassThru
        Write-Log "msiexec exit code: $($proc.ExitCode)"
    } else {
        Write-Log "Tiada MSI lokal. Cuba winget..."
        try {
            $proc = Start-Process "winget" -ArgumentList "install --id GLPI-Project.GLPI-Agent --silent --accept-source-agreements --accept-package-agreements" -NoNewWindow -PassThru -Wait
            Write-Log "winget exit code: $($proc.ExitCode)"
        } catch {
            Write-Log "RALAT: winget gagal: $($_.Exception.Message)"
            [System.Windows.Forms.MessageBox]::Show("Pemasangan gagal.", "Ralat", 0, 48)
            return
        }
    }
    # Configure
    Write-Log "Mengkonfigurasi agent.cfg..."
    $cfgDir = "$env:ProgramFiles\GLPI-Agent\etc"
    if (-not (Test-Path $cfgDir)) { New-Item -ItemType Directory -Path $cfgDir -Force | Out-Null }
    $cfgPath = "$cfgDir\agent.cfg"
    $cfgContent = "# Auto-configured by HBUK Script
server = $serverUrl
no-ssl-check = 1
listen = 0.0.0.0:62354
httpd-trust = 127.0.0.1/32
local = C:\Program Files\GLPI-Agent"
    Set-Content -Path $cfgPath -Value $cfgContent -Encoding UTF8 -Force
    Write-Log "[OK] agent.cfg dikonfigurasi."
    # Registry
    Write-Log "Menulis Registry tag..."
    $regPaths = @("HKLM:\SOFTWARE\GLPI-Agent", "HKLM:\SOFTWARE\WOW6432Node\GLPI-Agent")
    foreach ($rp in $regPaths) {
        if (-not (Test-Path $rp)) { New-Item -Path $rp -Force -EA SilentlyContinue | Out-Null }
        Set-ItemProperty -Path $rp -Name "server" -Value $serverUrl -Force -EA SilentlyContinue
        Set-ItemProperty -Path $rp -Name "tag" -Value $finalTag -Force -EA SilentlyContinue
    }
    Write-Log "[OK] Registry dikemaskini."
    # Restart service
    Write-Log "Memulakan semula GLPI Agent service..."
    Set-Service -Name "glpi-agent" -StartupType Automatic -EA SilentlyContinue
    Restart-Service -Name "glpi-agent" -Force -EA SilentlyContinue
    Write-Log "[OK] Service dimulakan semula."
    Write-Log "--- SELESAI: Pemasangan SPAI Agent ---"
    [System.Windows.Forms.MessageBox]::Show("Pemasangan SPAI Agent selesai!
Tag: $finalTag", "Berjaya", 0, 64)
    Update-SystemInfo
    Write-Log "Membuka browser ke http://localhost:62354/ ..."
    Start-Sleep -Seconds 1
    Start-Process "http://localhost:62354/"
}

# ==============================
# SPAI AUTO PANEL (Dropdown)
# ==============================
function New-LabeledComboBox($labelText, $y) {
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $labelText
    $lbl.Location = New-Object System.Drawing.Point(30, $y)
    $lbl.AutoSize = $true
    $lbl.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $cmb = New-Object System.Windows.Forms.ComboBox
    $cmb.Location = New-Object System.Drawing.Point(30, ($y + 25))
    $cmb.Size = New-Object System.Drawing.Size(600, 30)
    $cmb.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $cmb.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $panelSPAIAuto.Controls.Add($lbl)
    $panelSPAIAuto.Controls.Add($cmb)
    return $cmb
}

$glpiPaths = @(
    "KKM > JKN PERAK > HBUK > BAHAGIAN PENGURUSAN"
    "KKM > JKN PERAK > HBUK > BAHAGIAN PENGURUSAN > UNIT KESELAMATAN PELINDUNGAN"
    "KKM > JKN PERAK > HBUK > BAHAGIAN PENGURUSAN > UNIT KESELAMATAN PELINDUNGAN > BILIK KETUA UNIT"
    "KKM > JKN PERAK > HBUK > BAHAGIAN PENGURUSAN > UNIT KESELAMATAN PELINDUNGAN > PEJABAT"
    "KKM > JKN PERAK > HBUK > BAHAGIAN PENGURUSAN > UNIT KEWANGAN"
    "KKM > JKN PERAK > HBUK > BAHAGIAN PENGURUSAN > UNIT KEWANGAN > BILIK GAJI"
    "KKM > JKN PERAK > HBUK > BAHAGIAN PENGURUSAN > UNIT KEWANGAN > BILIK KETUA KERANI KEWANGAN"
    "KKM > JKN PERAK > HBUK > BAHAGIAN PENGURUSAN > UNIT KEWANGAN > BILIK KETUA UNIT"
    "KKM > JKN PERAK > HBUK > BAHAGIAN PENGURUSAN > UNIT KEWANGAN > BILIK PENOLONG AKAUNTAN"
    "KKM > JKN PERAK > HBUK > BAHAGIAN PENGURUSAN > UNIT KEWANGAN > BILIK VOT"
    "KKM > JKN PERAK > HBUK > BAHAGIAN PENGURUSAN > UNIT KEWANGAN > KUBIKEL PEJABAT"
    "KKM > JKN PERAK > HBUK > BAHAGIAN PENGURUSAN > UNIT KHIDMAT PENGURUSAN"
    "KKM > JKN PERAK > HBUK > BAHAGIAN PENGURUSAN > UNIT KHIDMAT PENGURUSAN > BILIK KETUA UNIT"
    "KKM > JKN PERAK > HBUK > BAHAGIAN PENGURUSAN > UNIT KHIDMAT PENGURUSAN > PEJABAT"
    "KKM > JKN PERAK > HBUK > BAHAGIAN PENGURUSAN > UNIT OPERASI"
    "KKM > JKN PERAK > HBUK > BAHAGIAN PENGURUSAN > UNIT OPERASI > UNIT KHIDMAT PELANGGAN"
    "KKM > JKN PERAK > HBUK > BAHAGIAN PENGURUSAN > UNIT OPERASI > UNIT KHIDMAT PELANGGAN > PEJABAT"
    "KKM > JKN PERAK > HBUK > BAHAGIAN PENGURUSAN > UNIT OPERASI > UNIT OPERASI"
    "KKM > JKN PERAK > HBUK > BAHAGIAN PENGURUSAN > UNIT OPERASI > UNIT OPERASI > PEJABAT"
    "KKM > JKN PERAK > HBUK > BAHAGIAN PENGURUSAN > UNIT OPERASI > UNIT PENGANGKUTAN DAN AMBULAN"
    "KKM > JKN PERAK > HBUK > BAHAGIAN PENGURUSAN > UNIT OPERASI > UNIT PENGANGKUTAN DAN AMBULAN > PEJABAT"
    "KKM > JKN PERAK > HBUK > BAHAGIAN PENGURUSAN > UNIT PEGURUSAN ASET DAN STOR"
    "KKM > JKN PERAK > HBUK > BAHAGIAN PENGURUSAN > UNIT PEGURUSAN ASET DAN STOR > BILIK KETUA UNIT"
    "KKM > JKN PERAK > HBUK > BAHAGIAN PENGURUSAN > UNIT PEGURUSAN ASET DAN STOR > PEJABAT UNIT ASET"
    "KKM > JKN PERAK > HBUK > BAHAGIAN PENGURUSAN > UNIT PEGURUSAN ASET DAN STOR > PEJABAT UNIT STOR"
    "KKM > JKN PERAK > HBUK > BAHAGIAN PENGURUSAN > UNIT PEMBANGUNAN"
    "KKM > JKN PERAK > HBUK > BAHAGIAN PENGURUSAN > UNIT PEMBANGUNAN > BILIK KETUA UNIT"
    "KKM > JKN PERAK > HBUK > BAHAGIAN PENGURUSAN > UNIT PEMBANGUNAN > PEJABAT"
    "KKM > JKN PERAK > HBUK > BAHAGIAN PENGURUSAN > UNIT PENGURUSAN MAKLUMAT"
    "KKM > JKN PERAK > HBUK > BAHAGIAN PENGURUSAN > UNIT PENGURUSAN MAKLUMAT > BILIK KETUA UNIT"
    "KKM > JKN PERAK > HBUK > BAHAGIAN PENGURUSAN > UNIT PENGURUSAN MAKLUMAT > MAKMAL KOMPUTER"
    "KKM > JKN PERAK > HBUK > BAHAGIAN PENGURUSAN > UNIT PENGURUSAN MAKLUMAT > PEJABAT JURUTEKNIK KOMPUTER"
    "KKM > JKN PERAK > HBUK > BAHAGIAN PENGURUSAN > UNIT PEROLEHAN"
    "KKM > JKN PERAK > HBUK > BAHAGIAN PENGURUSAN > UNIT PEROLEHAN > BILIK KETUA UNIT"
    "KKM > JKN PERAK > HBUK > BAHAGIAN PENGURUSAN > UNIT PEROLEHAN > PEJABAT"
    "KKM > JKN PERAK > HBUK > BAHAGIAN PENGURUSAN > UNIT PERPUSTAKAAN"
    "KKM > JKN PERAK > HBUK > BAHAGIAN PENGURUSAN > UNIT PERPUSTAKAAN > BILIK KETUA UNIT"
    "KKM > JKN PERAK > HBUK > BAHAGIAN PENGURUSAN > UNIT PERPUSTAKAAN > PEJABAT"
    "KKM > JKN PERAK > HBUK > BAHAGIAN PENGURUSAN > UNIT SUMBER MANUSIA"
    "KKM > JKN PERAK > HBUK > BAHAGIAN PENGURUSAN > UNIT SUMBER MANUSIA > BILIK FAIL"
    "KKM > JKN PERAK > HBUK > BAHAGIAN PENGURUSAN > UNIT SUMBER MANUSIA > BILIK PEGAWAI TADBIR DIPLOMATIK"
    "KKM > JKN PERAK > HBUK > BAHAGIAN PENGURUSAN > UNIT SUMBER MANUSIA > BILIK TATATERTIB"
    "KKM > JKN PERAK > HBUK > BAHAGIAN PENGURUSAN > UNIT SUMBER MANUSIA > BILIK TIMBALAN PENGARAH PENGURUSAN"
    "KKM > JKN PERAK > HBUK > BAHAGIAN PENGURUSAN > UNIT SUMBER MANUSIA > RUANGAN KUBIKEL PEJABAT"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UKKP"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UKKP > PEJABAT"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT DIETETIK DAN SAJIAN"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT DIETETIK DAN SAJIAN > DAPUR A"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT DIETETIK DAN SAJIAN > DAPUR A > BILIK SAJIAN"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT DIETETIK DAN SAJIAN > DAPUR A > STOR"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT DIETETIK DAN SAJIAN > DAPUR A > UNIT OPERASI"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT DIETETIK DAN SAJIAN > DAPUR B"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT DIETETIK DAN SAJIAN > DAPUR B > BILIK KETUA UNIT"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT DIETETIK DAN SAJIAN > DAPUR B > RUANG PEJABAT"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT FARMASI"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT FARMASI > FARMASI LOGISTIK"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT FARMASI > FARMASI LOGISTIK > BILIK FOTOSTAT"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT FARMASI > FARMASI LOGISTIK > BILIK KETUA UNIT"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT FARMASI > FARMASI LOGISTIK > BILIK PEGAWAI FARMASI 1"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT FARMASI > FARMASI LOGISTIK > BILIK PEGAWAI FARMASI 2"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT FARMASI > FARMASI LOGISTIK > RUANG PEJABAT"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT FARMASI > FARMASI PESAKIT DALAM"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT FARMASI > FARMASI PESAKIT DALAM > BILIK GALVANIKAL"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT FARMASI > FARMASI PESAKIT DALAM > BILIK KETUA UNIT"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT FARMASI > FARMASI PESAKIT DALAM > BILIK PEGAWAI FARMASI"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT FARMASI > FARMASI PESAKIT LUAR"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT FARMASI > FARMASI PESAKIT LUAR > BILIK KETUA UNIT"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT FARMASI > FARMASI PESAKIT LUAR > BILIK SUMBER"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT FARMASI > FARMASI PESAKIT LUAR > KAUNTER"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT FARMASI > FARMASI PESAKIT LUAR > PEJABAT"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT FARMASI > FARMASI PESAKIT LUAR > STOR UBAT"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT FISIOTERAPI"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT FISIOTERAPI > BILIK KETUA UNIT"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT FISIOTERAPI > BILIK KOMPUTER"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT FISIOTERAPI > BILIK PEGAWAI FISIO"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT FISIOTERAPI > RUANG ELEKTRO"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT FISIOTERAPI > RUANG GYM"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT HAL EHWAL ISLAM"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT HAL EHWAL ISLAM > KUBIKEL ARAS 2, KLINIK PAKAR"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT KEJURURAWATAN"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT KEJURURAWATAN > FA1-A2"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT KEJURURAWATAN > FA3-A4"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT KEJURURAWATAN > FA5-A6"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT KEJURURAWATAN > FA7-A8"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT KEJURURAWATAN > FW1"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT KEJURURAWATAN > FW12"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT KEJURURAWATAN > FW13"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT KEJURURAWATAN > FW14-15"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT KEJURURAWATAN > FW2-3"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT KEJURURAWATAN > FW4"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT KEJURURAWATAN > FW6"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT KEJURURAWATAN > FW7-8"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT KEJURURAWATAN > FW9-10"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT KEJURURAWATAN > KAWALAN INFEKSI"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT KEJURURAWATAN > MA1-A6"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT KEJURURAWATAN > MA7-A12"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT KEJURURAWATAN > UNIT KEJURURAWATAN"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT KEJURURAWATAN > WAD KEMASUKAN PEREMPUAN"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT KEJURURAWATAN > WAD KEMASUKAN PEREMPUAN > BILIK MATRON"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT KEJURURAWATAN > WAD KEMASUKAN PEREMPUAN > BILIK PRESENTASI"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT KEJURURAWATAN > WAD KEMASUKAN PEREMPUAN > BILIK WAD"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT KEJURUTERAAN"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT KEJURUTERAAN > PEJABAT"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT KERJA SOSIAL PERUBATAN"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT KERJA SOSIAL PERUBATAN > BILIK KETUA UNIT"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT KERJA SOSIAL PERUBATAN > PEJABAT"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT KUALITI"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT KUALITI > BILIK KETUA UNIT"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT KUALITI > PEJABAT"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT PATOLOGI"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT PATOLOGI > BILIK KETUA UNIT"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT PATOLOGI > BILIK MICRO"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT PATOLOGI > KAUNTER"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT PATOLOGI > MAKMAL"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT PEMULIHAN CARAKERJA"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT PEMULIHAN CARAKERJA > BENGKEL"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT PEMULIHAN CARAKERJA > DELIMA"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT PEMULIHAN CARAKERJA > UPCK MAIN"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT PEMULIHAN CARAKERJA > UPCK SE"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT PENYELIAAN"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT PENYELIAAN > KLINIK MATA"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT PENYELIAAN > KLINIK PAKAR"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT PENYELIAAN > MW1-2"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT PENYELIAAN > MW12-14"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT PENYELIAAN > MW15-17"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT PENYELIAAN > MW18-20"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT PENYELIAAN > MW21-25"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT PENYELIAAN > MW22-24"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT PENYELIAAN > MW23"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT PENYELIAAN > MW26-28"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT PENYELIAAN > MW3-5"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT PENYELIAAN > MW6-8"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT PENYELIAAN > MW9-11"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT PENYELIAAN > PKP"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT PENYELIAAN > PUSAT INFORMASI"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT PENYELIAAN > UNIT DISCAJ"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT PENYELIAAN > UNIT PENYELIAAN PPP"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT PENYELIAAN > WAD FORENSIK AKUT"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT PENYELIAAN > WAD KEBUN LELAKI"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT PENYELIAAN > WAD KEMASUKAN LELAKI"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT PSIKOLOGI DAN KAUNSELING"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT PSIKOLOGI DAN KAUNSELING > BILIK KETUA UNIT"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT PSIKOLOGI DAN KAUNSELING > BILIK PEGAWAI PSIKOLOGI"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT PSIKOLOGI DAN KAUNSELING > KUBIKEL ARAS 2, KLINIK PAKAR"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT RADIOLOGI"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT RADIOLOGI > BILIK XRAY"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT RADIOLOGI > RUANG PEJABAT"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT REKOD PERUBATAN"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT REKOD PERUBATAN > BILIK FAIL"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT REKOD PERUBATAN > BILIK KETUA UNIT"
    "KKM > JKN PERAK > HBUK > BAHAGIAN SOKONGAN KLINIKAL > UNIT REKOD PERUBATAN > RUANG PEJABAT"
    "KKM > JKN PERAK > HBUK > PEJABAT PENGARAH"
)

$cmbL1 = New-LabeledComboBox "1. Cawangan (Branch)" 45
$cmbL2 = New-LabeledComboBox "2. Unit Utama" 105
$cmbL3 = New-LabeledComboBox "3. Sub-Unit Lvl 1 (Jika Ada)" 165
$cmbL4 = New-LabeledComboBox "4. Sub-Unit Lvl 2 (Jika Ada)" 225

$lblGred = New-Object System.Windows.Forms.Label
$lblGred.Text = "5. Gred Jawatan (Cth: F9, UD13):"
$lblGred.Location = New-Object System.Drawing.Point(30, 285)
$lblGred.AutoSize = $true
$lblGred.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$panelSPAIAuto.Controls.Add($lblGred)

$txtGred = New-Object System.Windows.Forms.TextBox
$txtGred.Location = New-Object System.Drawing.Point(30, 310)
$txtGred.Size = New-Object System.Drawing.Size(200, 30)
$txtGred.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$panelSPAIAuto.Controls.Add($txtGred)

$lblTagPreview = New-Object System.Windows.Forms.Label
$lblTagPreview.Text = "TAG PREVIEW:"
$lblTagPreview.Location = New-Object System.Drawing.Point(30, 345)
$lblTagPreview.AutoSize = $true
$lblTagPreview.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$panelSPAIAuto.Controls.Add($lblTagPreview)

$txtPreview = New-Object System.Windows.Forms.TextBox
$txtPreview.Location = New-Object System.Drawing.Point(30, 365)
$txtPreview.Size = New-Object System.Drawing.Size(600, 40)
$txtPreview.Multiline = $true
$txtPreview.ReadOnly = $true
$txtPreview.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 240)
$txtPreview.Font = New-Object System.Drawing.Font("Consolas", 10)
$panelSPAIAuto.Controls.Add($txtPreview)

$btnPasangSPAI = New-Object System.Windows.Forms.Button
$btnPasangSPAI.Text = "Pasang SPAI"
$btnPasangSPAI.Location = New-Object System.Drawing.Point(30, 410)
$btnPasangSPAI.Size = New-Object System.Drawing.Size(600, 40)
$btnPasangSPAI.BackColor = [System.Drawing.Color]::FromArgb(27, 174, 112)
$btnPasangSPAI.ForeColor = [System.Drawing.Color]::White
$btnPasangSPAI.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$panelSPAIAuto.Controls.Add($btnPasangSPAI)

function Get-GLPIChildNode($prefix, $depthIndex) {
    $results = @()
    foreach ($p in $glpiPaths) {
        if ($p.StartsWith($prefix) -or $prefix -eq "KKM > JKN PERAK > HBUK") {
            $parts = $p -split " > "
            if ($parts.Length -gt $depthIndex) {
                $currentPrefix = ($parts[0..($depthIndex - 1)] -join " > ")
                if ($currentPrefix -eq $prefix) {
                    if ($results -notcontains $parts[$depthIndex]) { $results += $parts[$depthIndex] }
                }
            }
        }
    }
    return $results | Sort-Object
}

$l1Items = Get-GLPIChildNode "KKM > JKN PERAK > HBUK" 3
foreach ($i in $l1Items) { $cmbL1.Items.Add($i) | Out-Null }

$cmbL1.Add_SelectedIndexChanged({
    $cmbL2.Items.Clear(); $cmbL3.Items.Clear(); $cmbL4.Items.Clear()
    if ($cmbL1.SelectedItem) {
        $prefix = "KKM > JKN PERAK > HBUK > $($cmbL1.SelectedItem)"
        $items = Get-GLPIChildNode $prefix 4
        foreach ($i in $items) { $cmbL2.Items.Add($i) | Out-Null }
        $cmbL2.Enabled = ($items.Count -gt 0)
        $cmbL3.Enabled = $false; $cmbL4.Enabled = $false
    }
    Update-TagPreview
})
$cmbL2.Add_SelectedIndexChanged({
    $cmbL3.Items.Clear(); $cmbL4.Items.Clear()
    if ($cmbL2.SelectedItem) {
        $prefix = "KKM > JKN PERAK > HBUK > $($cmbL1.SelectedItem) > $($cmbL2.SelectedItem)"
        $items = Get-GLPIChildNode $prefix 5
        foreach ($i in $items) { $cmbL3.Items.Add($i) | Out-Null }
        $cmbL3.Enabled = ($items.Count -gt 0)
        $cmbL4.Enabled = $false
    }
    Update-TagPreview
})
$cmbL3.Add_SelectedIndexChanged({
    $cmbL4.Items.Clear()
    if ($cmbL3.SelectedItem) {
        $prefix = "KKM > JKN PERAK > HBUK > $($cmbL1.SelectedItem) > $($cmbL2.SelectedItem) > $($cmbL3.SelectedItem)"
        $items = Get-GLPIChildNode $prefix 6
        foreach ($i in $items) { $cmbL4.Items.Add($i) | Out-Null }
        $cmbL4.Enabled = ($items.Count -gt 0)
    }
    Update-TagPreview
})
$cmbL4.Add_SelectedIndexChanged({ Update-TagPreview })
$txtGred.Add_TextChanged({ Update-TagPreview })

function Update-TagPreview {
    $tag = "KKM > JKN PERAK > HOSPITAL BAHAGIA ULU KINTA"
    if ($cmbL1.SelectedItem) { $tag += " > $($cmbL1.SelectedItem)" }
    if ($cmbL2.SelectedItem) { $tag += " > $($cmbL2.SelectedItem)" }
    if ($cmbL3.SelectedItem) { $tag += " > $($cmbL3.SelectedItem)" }
    if ($cmbL4.SelectedItem) { $tag += " > $($cmbL4.SelectedItem)" }
    if ($txtGred.Text -ne "") { $tag += " > $($txtGred.Text)" }
    $tag += " > $env:COMPUTERNAME"
    $txtPreview.Text = $tag
}

$btnPasangSPAI.Add_Click({
    if ([string]::IsNullOrWhiteSpace($txtGred.Text)) {
        [System.Windows.Forms.MessageBox]::Show("Sila masukkan Gred Jawatan!", "Peringatan", 0, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }
    # Simpan tag terakhir untuk sejarah (F-07)
    $tagHistoryFile = Join-Path $env:HBUK_BASE_DIR "packages\config\spai_tag_history.txt"
    try { Add-Content -Path $tagHistoryFile -Value $txtPreview.Text -ErrorAction SilentlyContinue } catch {}
    Install-SPAIWithTag $txtPreview.Text
})

# ==============================
# SPAI MANUAL PANEL
# ==============================
$lblManInfo = New-Object System.Windows.Forms.Label
$lblManInfo.Text = "Masukkan maklumat secara manual. Prefix tetap:
KKM > JKN PERAK > HOSPITAL BAHAGIA ULU KINTA >"
$lblManInfo.Location = New-Object System.Drawing.Point(30, 45)
$lblManInfo.AutoSize = $true
$lblManInfo.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$panelSPAIManual.Controls.Add($lblManInfo)

function New-ManualField($labelText, $y) {
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $labelText
    $lbl.Location = New-Object System.Drawing.Point(30, $y)
    $lbl.AutoSize = $true
    $lbl.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Location = New-Object System.Drawing.Point(30, ($y + 22))
    $txt.Size = New-Object System.Drawing.Size(600, 28)
    $txt.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $panelSPAIManual.Controls.Add($lbl)
    $panelSPAIManual.Controls.Add($txt)
    return $txt
}

$txtManBahagian = New-ManualField "Bahagian (Cth: BAHAGIAN PENGURUSAN):" 90
$txtManUnit = New-ManualField "Unit (Cth: UNIT PENGURUSAN MAKLUMAT):" 145
$txtManSubUnit = New-ManualField "Sub-Unit (Jika Ada):" 200
$txtManGred = New-ManualField "Gred Jawatan (Cth: F9, UD13):" 255

$lblManPreview = New-Object System.Windows.Forms.Label
$lblManPreview.Text = "TAG PREVIEW:"
$lblManPreview.Location = New-Object System.Drawing.Point(30, 310)
$lblManPreview.AutoSize = $true
$lblManPreview.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$panelSPAIManual.Controls.Add($lblManPreview)

$txtManPreview = New-Object System.Windows.Forms.TextBox
$txtManPreview.Location = New-Object System.Drawing.Point(30, 332)
$txtManPreview.Size = New-Object System.Drawing.Size(600, 40)
$txtManPreview.Multiline = $true
$txtManPreview.ReadOnly = $true
$txtManPreview.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 240)
$txtManPreview.Font = New-Object System.Drawing.Font("Consolas", 10)
$panelSPAIManual.Controls.Add($txtManPreview)

function Update-ManualTagPreview {
    $tag = "KKM > JKN PERAK > HOSPITAL BAHAGIA ULU KINTA"
    if ($txtManBahagian.Text) { $tag += " > $($txtManBahagian.Text.ToUpper())" }
    if ($txtManUnit.Text) { $tag += " > $($txtManUnit.Text.ToUpper())" }
    if ($txtManSubUnit.Text) { $tag += " > $($txtManSubUnit.Text.ToUpper())" }
    if ($txtManGred.Text) { $tag += " > $($txtManGred.Text.ToUpper())" }
    $tag += " > $env:COMPUTERNAME"
    $txtManPreview.Text = $tag
}

$txtManBahagian.Add_TextChanged({ Update-ManualTagPreview })
$txtManUnit.Add_TextChanged({ Update-ManualTagPreview })
$txtManSubUnit.Add_TextChanged({ Update-ManualTagPreview })
$txtManGred.Add_TextChanged({ Update-ManualTagPreview })

$btnPasangSPAIManual = New-Object System.Windows.Forms.Button
$btnPasangSPAIManual.Text = "Pasang SPAI (Manual Tag)"
$btnPasangSPAIManual.Location = New-Object System.Drawing.Point(30, 385)
$btnPasangSPAIManual.Size = New-Object System.Drawing.Size(600, 40)
$btnPasangSPAIManual.BackColor = [System.Drawing.Color]::FromArgb(27, 174, 112)
$btnPasangSPAIManual.ForeColor = [System.Drawing.Color]::White
$btnPasangSPAIManual.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$panelSPAIManual.Controls.Add($btnPasangSPAIManual)

$btnPasangSPAIManual.Add_Click({
    if ([string]::IsNullOrWhiteSpace($txtManGred.Text)) {
        [System.Windows.Forms.MessageBox]::Show("Sila masukkan Gred Jawatan!", "Peringatan", 0, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }
    Install-SPAIWithTag $txtManPreview.Text
})

# -------------------------------------------------------------
# PANEL 3: PENGURUSAN RUSTDESK
# -------------------------------------------------------------
$panelRustDesk = New-Object System.Windows.Forms.Panel
$panelRustDesk.Size = $panelContent.Size
$panelRustDesk.Location = New-Object System.Drawing.Point(0, 0)
$panelRustDesk.Visible = $false

$lblRD = New-Object System.Windows.Forms.Label
$lblRD.Text = "Pengurusan RustDesk"
$lblRD.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
$lblRD.Location = New-Object System.Drawing.Point(30, 30)
$lblRD.AutoSize = $true
$panelRustDesk.Controls.Add($lblRD)

# Helper function to set RustDesk permanent password reliably
function Set-RustDeskPassword($passcode) {
    $rd = "$env:ProgramFiles\RustDesk\rustdesk.exe"
    if (-not (Test-Path $rd)) { $rd = "${env:ProgramFiles(x86)}\RustDesk\rustdesk.exe" }
    if (-not (Test-Path $rd)) { Write-Log "RALAT: rustdesk.exe tidak dijumpai."; return $false }
    
    # Method: Use cmd.exe to run rustdesk --password (avoids PowerShell argument issues)
    Write-Log "Menetapkan kata laluan kekal via cmd..."
    cmd.exe /c "`"$rd`" --password `"$passcode`"" 2>$null
    Start-Sleep -Seconds 2
    
    # Set verification method
    cmd.exe /c "`"$rd`" --option verification-method use-both-passwords" 2>$null
    Start-Sleep -Seconds 1
    Write-Log "Verification method: use-both-passwords"
    
    # Verify password was set by checking TOML for password hash
    $toml = 'C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\RustDesk\config\RustDesk2.toml'
    if (Test-Path $toml) {
        $content = Get-Content $toml -Raw
        if ($content -match 'password') {
            Write-Log "[OK] Password hash dijumpai dalam config."
            return $true
        }
    }
    Write-Log "AMARAN: Password hash tidak disahkan dalam TOML."
    return $true
}

function New-RustButton($text, $y) {
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $text
    $btn.Location = New-Object System.Drawing.Point(30, $y)
    $btn.Size = New-Object System.Drawing.Size(600, 45)
    $btn.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $panelRustDesk.Controls.Add($btn)
    return $btn
}

$btnRDInstall = New-RustButton "1. Pasang atau Kemaskini RustDesk" 80
$btnRDInstall.Add_Click({
        Write-Log "--- MULA: Pemasangan RustDesk ---"
        $rdFiles = try { [System.IO.Directory]::GetFiles("$env:HBUK_BASE_DIR\packages\installer", "rustdesk-*.msi") } catch { @() }
        $localMsi = if ($rdFiles.Count -gt 0) { New-Object System.IO.FileInfo ($rdFiles | Sort-Object | Select-Object -Last 1) } else { $null }
        $msiToInstall = $null
    
        # Step 1: Check internet & online version
        Write-Log "Memeriksa sambungan internet..."
        $hasInternet = $false
        try { $null = Invoke-WebRequest -Uri "https://api.github.com" -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop; $hasInternet = $true } catch {}
    
        if ($hasInternet) {
            Write-Log "Internet: TERSAMBUNG. Memeriksa versi terkini di GitHub..."
            try {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                $api = Invoke-RestMethod -Uri "https://api.github.com/repos/rustdesk/rustdesk/releases/latest" -ErrorAction Stop
                $onlineVer = $api.tag_name -replace '[^0-9.]', ''
                $localVer = if ($localMsi -and $localMsi.Name -match '(\d+\.\d+\.\d+)') { $matches[1] } else { "0.0.0" }
                Write-Log "Versi online: $onlineVer | Versi lokal MSI: $localVer"
            
                if ([version]$onlineVer -gt [version]$localVer) {
                    $ask = [System.Windows.Forms.MessageBox]::Show("Versi terkini $onlineVer tersedia (lokal: $localVer).`nMuat turun versi baru?", "Kemaskini Tersedia", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
                    if ($ask -eq [System.Windows.Forms.DialogResult]::Yes) {
                        $msiAsset = $api.assets | Where-Object { $_.name -match "rustdesk-.*x86_64.*\.msi$" } | Select-Object -First 1
                        if ($msiAsset) {
                            $dlPath = Join-Path "$env:HBUK_BASE_DIR\packages\installer" $msiAsset.name
                            Write-Log "Memuat turun $($msiAsset.name)..."
                            Invoke-WebRequest -Uri $msiAsset.browser_download_url -OutFile $dlPath -ErrorAction Stop
                            Write-Log "Muat turun selesai: $dlPath"
                            $msiToInstall = $dlPath
                        }
                        else { Write-Log "AMARAN: MSI tidak dijumpai dalam release GitHub. Guna lokal." }
                    }
                }
                else { Write-Log "Versi lokal sudah terkini." }
            }
            catch { Write-Log "AMARAN: Gagal semak GitHub: $($_.Exception.Message)" }
        }
        else {
            Write-Log "Internet: TIADA SAMBUNGAN. Menggunakan MSI lokal."
        }
    
        # Step 2: Use local MSI if no download
        if (-not $msiToInstall) {
            if ($localMsi) { $msiToInstall = $localMsi.FullName; Write-Log "Menggunakan MSI lokal: $($localMsi.Name)" }
            else { Write-Log "RALAT: Tiada MSI dijumpai!"; [System.Windows.Forms.MessageBox]::Show("Tiada fail MSI RustDesk dijumpai.", "Ralat", 0, 48); return }
        }
    
        # Step 3: Clean up any ghost installations first
        $ghostKeys = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*RustDesk*" }
        if ($ghostKeys) {
            $ghostGuid = ($ghostKeys | Select-Object -First 1).PSChildName
            Write-Log "Membersihkan pemasangan lama (GUID: $ghostGuid)..."
            $proc = Start-Process "msiexec.exe" -ArgumentList "/x $ghostGuid /qn /norestart" -Wait -PassThru
            Write-Log "Cleanup exit code: $($proc.ExitCode)"
            Start-Sleep -Seconds 2
        }
    
        # Step 4: Fresh install via msiexec
        Write-Log "Memasang RustDesk via msiexec... Sila tunggu."
        $logPath = Join-Path $script:LogFolder "RustDesk-Install-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
        $msiArgs = "/i `"$msiToInstall`" /qn /norestart /L*v `"$logPath`""
        $proc = Start-Process "msiexec.exe" -ArgumentList $msiArgs -Wait -PassThru
        Write-Log "msiexec exit code: $($proc.ExitCode)"
    
        # Step 5: Verify installation actually worked
        Start-Sleep -Seconds 3
        $rdExeCheck = "$env:ProgramFiles\RustDesk\rustdesk.exe"
        if (-not (Test-Path $rdExeCheck)) { $rdExeCheck = "${env:ProgramFiles(x86)}\RustDesk\rustdesk.exe" }
    
        if (Test-Path $rdExeCheck) {
            Write-Log "[OK] RustDesk berjaya dipasang di: $rdExeCheck"
        
            # Start service and tray
            Write-Log "Memulakan RustDesk service..."
            sc.exe start RustDesk 2>$null | Out-Null
            Start-Process $rdExeCheck -ArgumentList "--tray" -WindowStyle Hidden -ErrorAction SilentlyContinue
            Write-Log "[OK] RustDesk dimulakan."
        }
        else {
            Write-Log "[!] AMARAN: rustdesk.exe TIDAK dijumpai selepas pemasangan!"
            Write-Log "[!] Semak log MSI: $logPath"
            [System.Windows.Forms.MessageBox]::Show("Pemasangan mungkin gagal. rustdesk.exe tidak dijumpai.`nSemak log: $logPath", "Amaran", 0, 48)
        }
    
        Update-SystemInfo
        Write-Log "--- SELESAI: Pemasangan RustDesk ---"

        # Animated toast notification pada kejayaan pemasangan
        if (Test-Path $rdExeCheck) {
            $rdVerToast = try { (Get-Item $rdExeCheck).VersionInfo.FileVersion -replace '\+.*','' } catch { 'N/A' }
            Show-ToastNotification "RustDesk $rdVerToast berjaya dipasang dan dimulakan." "Pemasangan Berjaya" 3000
        }
    })

$btnRDConfig = New-RustButton "2. Tetapan Konfigurasi RustDesk HBUK" 140
$btnRDConfig.Add_Click({
        Write-Log "--- MULA: Konfigurasi RustDesk HBUK ---"
        $cfg = "$env:HBUK_BASE_DIR\packages\config\rustdesk_config.txt"
        if (-not (Test-Path $cfg)) {
            Write-Log "RALAT: rustdesk_config.txt tidak dijumpai."
            [System.Windows.Forms.MessageBox]::Show("Fail packages\config\rustdesk_config.txt tiada.`n`nSila cipta fail ini dengan format:`nID_SERVER=x.x.x.x`nRELAY_SERVER=x.x.x.x`nKEY=xxx`nPASSWORD=xxx", "Ralat", 0, 48)
            return
        }
    
        $idSrv = ""; $relaySrv = ""; $key = ""; $pw = ""
        foreach ($line in Get-Content $cfg) {
            $line = $line.Trim()
            if ($line -match "^#" -or $line -eq "") { continue }
            if ($line -match "^ID_SERVER=(.*)") { $idSrv = $matches[1].Trim() }
            if ($line -match "^RELAY_SERVER=(.*)") { $relaySrv = $matches[1].Trim() }
            if ($line -match "^KEY=(.*)") { $key = $matches[1].Trim() }
            if ($line -match "^PASSWORD=(.*)") { $pw = $matches[1].Trim() }
        }
    
        if (-not $idSrv) {
            Write-Log "RALAT: ID_SERVER tidak dijumpai dalam config."
            [System.Windows.Forms.MessageBox]::Show("ID_SERVER tidak dijumpai dalam rustdesk_config.txt.", "Ralat", 0, 48); return
        }
    
        Write-Log "Config: Server=$idSrv | Relay=$relaySrv | Password=$(if($pw){'***set***'}else{'tiada'})"
    
        # Confirm
        $msg = "Konfigurasi dari rustdesk_config.txt:`n`nServer: $idSrv`nRelay: $relaySrv`nPassword: $(if($pw){'***set***'}else{'Tiada'})`n`nAplikasikan konfigurasi ini?"
        $confirm = [System.Windows.Forms.MessageBox]::Show($msg, "Sahkan Konfigurasi", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { Write-Log "Dibatalkan."; return }
    
        # Stop RustDesk
        Write-Log "Menghentikan RustDesk..."
        sc.exe stop RustDesk 2>$null | Out-Null
        Stop-Process -Name rustdesk -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    
        # Write TOML config
        Write-Log "Menulis konfigurasi TOML..."
        $paths = @('C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\RustDesk\config\RustDesk.toml', 'C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\RustDesk\config\RustDesk2.toml')
        foreach ($p in $paths) {
            $dir = Split-Path $p -Parent
            if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        
            $existingId = $null
            if (Test-Path $p) {
                foreach ($l in Get-Content $p) {
                    if ($l -match "^id\s*=") { $existingId = $l; break }
                }
            }
            $template = @(
                "rendezvous_server = '$idSrv`:21116'",
                "nat_type = 1",
                "serial = 0",
                "",
                "[options]",
                "direct-server = 'Y'",
                "relay-server = '$relaySrv'",
                "custom-rendezvous-server = '$idSrv'",
                "direct-access-port = '21118'",
                "key = '$key'",
                "av1-test = 'Y'",
                "verification-method = 'use-both-passwords'"
            )
            $finalContent = @()
            if ($existingId) { $finalContent += $existingId }
            $finalContent += $template
            $finalContent | Set-Content -Path $p -Encoding UTF8
        }
        Write-Log "[OK] TOML dikemaskini."
    
        # Ujian sambungan ke server RustDesk (F-09)
        Write-Log "Menguji sambungan ke server RustDesk ($idSrv)..."
        $pingResult = Test-Connection -ComputerName $idSrv -Count 2 -ErrorAction SilentlyContinue
        if ($pingResult) {
            $avgMs = [Math]::Round(($pingResult | Measure-Object -Property ResponseTime -Average).Average, 1)
            Write-Log "[OK] Server $idSrv boleh dicapai. Latency: ${avgMs}ms"
        } else {
            Write-Log "AMARAN: Server $idSrv TIDAK boleh dicapai (ping gagal). Semak rangkaian."
        }
    
        # Restart Service FIRST so password can be set
        sc.exe start RustDesk 2>$null | Out-Null
        Start-Sleep -Seconds 2
    
        # Set permanent password if defined in config
        $rd = "$env:ProgramFiles\RustDesk\rustdesk.exe"
        if (-not (Test-Path $rd)) { $rd = "${env:ProgramFiles(x86)}\RustDesk\rustdesk.exe" }
        if ($pw -and (Test-Path $rd)) {
            $result = Set-RustDeskPassword $pw
            if ($result) { Write-Log "[OK] Kata laluan kekal ditetapkan." }
            else { Write-Log "AMARAN: Gagal menetapkan kata laluan." }
        }
    
        if (Test-Path $rd) { Start-Process $rd -ArgumentList "--tray" -WindowStyle Hidden -ErrorAction SilentlyContinue }
    
        Update-SystemInfo
        Write-Log "[OK] Konfigurasi HBUK berjaya diaplikasikan!"
        [System.Windows.Forms.MessageBox]::Show("Konfigurasi HBUK berjaya diaplikasikan!`nServer, key, dan kata laluan telah ditetapkan.", "Berjaya", 0, 64)
        Write-Log "--- SELESAI: Konfigurasi RustDesk HBUK ---"
    })

$btnRDTukarID = New-RustButton "3. Tukar RustDesk ID" 200
$btnRDTukarID.Add_Click({
        Write-Log "--- MULA: Tukar RustDesk ID ---"
        $rd = "$env:ProgramFiles\RustDesk\rustdesk.exe"
        if (-not (Test-Path $rd)) { $rd = "${env:ProgramFiles(x86)}\RustDesk\rustdesk.exe" }
        if (-not (Test-Path $rd)) {
            Write-Log "RALAT: RustDesk tidak dipasang."
            [System.Windows.Forms.MessageBox]::Show("RustDesk tidak dipasang.", "Ralat", 0, 48); return
        }
    
        $cleanHost = ($env:COMPUTERNAME).Replace("-", "")
        $currentId = try { & $rd --get-id 2>$null } catch { "N/A" }
        $randomId = -join ((48..57) | Get-Random -Count 9 | ForEach-Object { [char]$_ })
    
        $msg = "ID Semasa: $currentId`n`nPilih ID baharu:`n`n[1] Guna Nama PC ($cleanHost)`n[2] Guna Nombor Rawak ($randomId)`n[3] Masukkan ID Manual`n`nMasukkan pilihan (1/2/3):"
        $choice = [Microsoft.VisualBasic.Interaction]::InputBox($msg, "Tukar RustDesk ID", "1")
    
        $newId = ""
        switch ($choice) {
            "1" { $newId = $cleanHost }
            "2" { $newId = $randomId }
            "3" {
                $newId = [Microsoft.VisualBasic.Interaction]::InputBox("Masukkan ID baharu:", "ID Manual", "")
                if (-not $newId) { Write-Log "Dibatalkan."; return }
            }
            default { return }
        }
    
        $confirm = [System.Windows.Forms.MessageBox]::Show("Tukar ID kepada: $newId`n`nTeruskan?", "Sahkan", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { Write-Log "Dibatalkan."; return }
    
        Write-Log "Menukar ID kepada: $newId"
        sc.exe stop RustDesk 2>$null | Out-Null
        Stop-Process -Name rustdesk -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
    
        # Check for custom-rustdesk tool
        $customRdTool = "$env:HBUK_BASE_DIR\packages\tools\custom-rustdesk-windows-x86_64.exe"
        $generatedEncId = ""
        if (Test-Path $customRdTool) {
            Write-Log "Alat custom-rustdesk dijumpai. Menjana enc_id..."
            $uuid = (Get-ItemProperty -Path Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Cryptography).MachineGuid
            if ($uuid) {
                $generatedEncId = & $customRdTool --id $newId --uuid $uuid
                if ($generatedEncId) {
                    $generatedEncId = $generatedEncId.Trim()
                    Write-Log "Berjaya menjana enc_id: $generatedEncId"
                }
                else {
                    Write-Log "AMARAN: custom-rustdesk gagal menjana enc_id."
                }
            }
            else {
                Write-Log "AMARAN: Gagal mendapatkan MachineGuid."
            }
        }
        else {
            Write-Log "custom-rustdesk tidak dijumpai di $customRdTool. Menggunakan kaedah plain text id."
        }
    
        # Build list of ALL config paths (LocalService + all user profiles)
        $paths = @(
            'C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\RustDesk\config\RustDesk.toml',
            'C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\RustDesk\config\RustDesk2.toml'
        )
        $userProfiles = Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue
        foreach ($pfe in $userProfiles) {
            $paths += "$($pfe.FullName)\AppData\Roaming\RustDesk\config\RustDesk.toml"
            $paths += "$($pfe.FullName)\AppData\Roaming\RustDesk\config\RustDesk2.toml"
        }
    
        $updated = 0
        foreach ($p in $paths) {
            # Create config directory if it doesn't exist (ensures all user profiles get the ID)
            $dir = Split-Path $p -Parent
            if (-not (Test-Path $dir)) {
                New-Item -ItemType Directory -Path $dir -Force -ErrorAction SilentlyContinue | Out-Null
                Write-Log "  Cipta direktori: $dir"
            }

            if (Test-Path $p) {
                $content = Get-Content $p
                $newContent = @(); $foundEnc = $false; $foundId = $false
                foreach ($l in $content) {
                    if ($generatedEncId) {
                        if ($l -match "^enc_id\s*=") { 
                            $newContent += "enc_id = '$generatedEncId'"
                            $foundEnc = $true 
                        }
                        elseif ($l -match "^id\s*=") { Write-Log "  Removed plain text id from: $p" }
                        elseif ($l -match "^# id_plaintext\s*=") { } # buang lama
                        else { $newContent += $l }
                    }
                    else {
                        if ($l -match "^id\s*=") { $newContent += "id = '$newId'"; $foundId = $true }
                        elseif ($l -match "^enc_id\s*=") { Write-Log "  Removed enc_id from: $p" }
                        elseif ($l -match "^# id_plaintext\s*=") { } # buang lama
                        else { $newContent += $l }
                    }
                }
                if ($generatedEncId -and -not $foundEnc) { 
                    $newContent = @("enc_id = '$generatedEncId'") + $newContent 
                }
                if (-not $generatedEncId -and -not $foundId) { $newContent = @("id = '$newId'") + $newContent }
                
                $newContent | Set-Content $p -Encoding UTF8
            }
            else {
                # Create new config file with ID for users who haven't run RustDesk yet
                if ($generatedEncId) {
                    "enc_id = '$generatedEncId'" | Set-Content $p -Encoding UTF8
                }
                else {
                    "id = '$newId'" | Set-Content $p -Encoding UTF8
                }
            }
            Write-Log "  Updated: $p"
            $updated++
        }

        # Simpan plain text ID secara kekal dalam fail berasingan
        $idFile = "C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\RustDesk\config\HBUK_ID.txt"
        try {
            $newId | Set-Content $idFile -Force -Encoding UTF8
        }
        catch {}

        Write-Log "Jumlah fail dikemaskini: $updated"
    
        Start-Sleep -Seconds 2
        sc.exe start RustDesk 2>$null | Out-Null
        Start-Sleep -Seconds 2
        Start-Process $rd -ArgumentList "--tray" -WindowStyle Hidden -ErrorAction SilentlyContinue
    
        Update-SystemInfo
        Write-Log "[OK] ID ditukar kepada: $newId"
        [System.Windows.Forms.MessageBox]::Show("ID berjaya ditukar kepada: $newId`n`n(Jika ID masih tidak berubah, sila restart PC)", "Berjaya", 0, 64)
        Write-Log "--- SELESAI: Tukar RustDesk ID ---"
    })

$btnRDPassword = New-RustButton "4. Tetapkan Kata Laluan Manual" 260
$btnRDPassword.Add_Click({
        Write-Log "--- MULA: Tetapkan Kata Laluan Manual ---"
        $rd = "$env:ProgramFiles\RustDesk\rustdesk.exe"
        if (-not (Test-Path $rd)) { $rd = "${env:ProgramFiles(x86)}\RustDesk\rustdesk.exe" }
        if (-not (Test-Path $rd)) {
            Write-Log "RALAT: RustDesk tidak dipasang."
            [System.Windows.Forms.MessageBox]::Show("RustDesk tidak dipasang.", "Ralat", 0, 48); return
        }
    
        $pw = [Microsoft.VisualBasic.Interaction]::InputBox("Masukkan kata laluan kekal baharu:`n`n(Kata laluan ini membolehkan admin remote tanpa perlu pengguna approve)", "Kata Laluan Kekal RustDesk", "")
        if (-not $pw) { Write-Log "Dibatalkan."; return }
    
        # Confirm
        $confirm = [System.Windows.Forms.MessageBox]::Show("Tetapkan kata laluan kekal kepada:`n$pw`n`nTeruskan?", "Sahkan", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { Write-Log "Dibatalkan."; return }
    
        # Ensure service is running before setting password
        Write-Log "Memastikan RustDesk berjalan..."
        sc.exe start RustDesk 2>$null | Out-Null
        Start-Sleep -Seconds 2
    
        $result = Set-RustDeskPassword $pw
        if (-not $result) { Write-Log "AMARAN: Gagal menetapkan kata laluan." }
    
        Start-Process $rd -ArgumentList "--tray" -WindowStyle Hidden -ErrorAction SilentlyContinue
    
        Write-Log "[OK] Kata laluan kekal: $pw"
        [System.Windows.Forms.MessageBox]::Show("Kata laluan kekal berjaya ditetapkan!`nAdmin boleh remote menggunakan password ini.", "Berjaya", 0, 64)
        Write-Log "--- SELESAI: Tetapkan Kata Laluan Manual ---"
    })

$btnRDUninstall = New-RustButton "5. Nyahpasang RustDesk (Bersih Penuh)" 320
$btnRDUninstall.Add_Click({
        Write-Log "--- MULA: Nyahpasang RustDesk (BERSIH PENUH) ---"
    
        $confirm = [System.Windows.Forms.MessageBox]::Show("Ini akan memadam RustDesk sepenuhnya termasuk semua config, ID, dan kata laluan.`n`nTeruskan?", "Pengesahan", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
        if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { Write-Log "Dibatalkan oleh pengguna."; return }
    
        # 1. Stop service and kill process
        Write-Log "[1/6] Menghentikan RustDesk service dan proses..."
        sc.exe stop RustDesk 2>$null | Out-Null
        Stop-Process -Name rustdesk -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    
        # 2. MSI/EXE uninstall via registry
        Write-Log "[2/6] Menjalankan uninstaller rasmi..."
        $unKeys = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*RustDesk*" }
        if ($unKeys) {
            foreach ($entry in $unKeys) {
                $guid = $entry.PSChildName
                Write-Log "  Uninstall GUID: $guid"
                $proc = Start-Process "msiexec.exe" -ArgumentList "/x $guid /qn /norestart" -Wait -PassThru
                Write-Log "  msiexec exit code: $($proc.ExitCode)"
            }
            Start-Sleep -Seconds 2
        }
        else { Write-Log "  Tiada entry uninstall dijumpai dalam Registry." }
    
        # 3. Delete RustDesk service
        Write-Log "[3/6] Membuang RustDesk service..."
        sc.exe delete RustDesk 2>$null | Out-Null
    
        # 4. Remove install directories
        Write-Log "[4/6] Membuang folder pemasangan..."
        $installDirs = @(
            "$env:ProgramFiles\RustDesk",
            "${env:ProgramFiles(x86)}\RustDesk"
        )
        foreach ($dir in $installDirs) {
            if (Test-Path $dir) {
                Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
                Write-Log "  Dipadam: $dir"
            }
        }
    
        # 5. Remove ALL config/data folders
        Write-Log "[5/6] Membersihkan semua folder konfigurasi..."
        $configDirs = @(
            "C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\RustDesk",
            "$env:ProgramData\RustDesk"
        )
        # Also clean all user profiles
        $userProfiles = Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue
        foreach ($pfe in $userProfiles) {
            $configDirs += "$($pfe.FullName)\AppData\Roaming\RustDesk"
        }
        foreach ($dir in $configDirs) {
            if (Test-Path $dir) {
                Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
                Write-Log "  Dipadam: $dir"
            }
        }
    
        # 6. Clean ALL registry traces
        Write-Log "[6/6] Membersihkan semua Registry traces..."
        $regPaths = @(
            "HKLM:\SOFTWARE\RustDesk",
            "HKLM:\SOFTWARE\WOW6432Node\RustDesk",
            "HKCU:\SOFTWARE\RustDesk"
        )
        foreach ($rp in $regPaths) {
            if (Test-Path $rp) {
                Remove-Item $rp -Recurse -Force -ErrorAction SilentlyContinue
                Write-Log "  Registry dipadam: $rp"
            }
        }
        # Clean leftover uninstall entries
        $leftover = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*RustDesk*" }
        foreach ($entry in $leftover) {
            $keyPath = $entry.PSPath
            Remove-Item $keyPath -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "  Registry uninstall entry dipadam: $($entry.PSChildName)"
        }
    
        Write-Log "[OK] RustDesk telah dinyahpasang sepenuhnya. Tiada traces ditinggalkan."
        [System.Windows.Forms.MessageBox]::Show("RustDesk telah dinyahpasang sepenuhnya!`nSemua config, ID, kata laluan, dan registry telah dibersihkan.", "Berjaya", 0, 64)
    
        Update-SystemInfo
        Write-Log "--- SELESAI: Nyahpasang RustDesk ---"
    })


# -------------------------------------------------------------
# PANEL 4: PENGURUSAN PENGGUNA
# -------------------------------------------------------------
$panelUser = New-Object System.Windows.Forms.Panel
$panelUser.Size = $panelContent.Size
$panelUser.Location = New-Object System.Drawing.Point(0, 0)
$panelUser.Visible = $false

$lblUser = New-Object System.Windows.Forms.Label
$lblUser.Text = "Pengurusan PC & Pengguna"
$lblUser.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
$lblUser.Location = New-Object System.Drawing.Point(30, 30)
$lblUser.AutoSize = $true
$panelUser.Controls.Add($lblUser)

$lblHost = New-Object System.Windows.Forms.Label
$lblHost.Text = "Tukar Hostname Komputer:"
$lblHost.Location = New-Object System.Drawing.Point(30, 80)
$lblHost.AutoSize = $true
$lblHost.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$panelUser.Controls.Add($lblHost)

$txtHostname = New-Object System.Windows.Forms.TextBox
$txtHostname.Location = New-Object System.Drawing.Point(30, 105)
$txtHostname.Size = New-Object System.Drawing.Size(200, 30)
$txtHostname.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$txtHostname.Text = $env:COMPUTERNAME
$panelUser.Controls.Add($txtHostname)

$btnChangeHost = New-Object System.Windows.Forms.Button
$btnChangeHost.Location = New-Object System.Drawing.Point(240, 104)
$btnChangeHost.Size = New-Object System.Drawing.Size(120, 28)
$btnChangeHost.Text = "Tukar Nama"
$btnChangeHost.BackColor = [System.Drawing.Color]::FromArgb(41, 128, 185)
$btnChangeHost.ForeColor = [System.Drawing.Color]::White
$btnChangeHost.Add_Click({
        if ([string]::IsNullOrWhiteSpace($txtHostname.Text)) { return }
        Rename-Computer -NewName $txtHostname.Text.ToUpper() -Force -ErrorAction SilentlyContinue
        [System.Windows.Forms.MessageBox]::Show("Hostname berjaya ditukar kepada " + $txtHostname.Text.ToUpper() + ". Sila restart PC selepas ini.", "Berjaya", 0, [System.Windows.Forms.MessageBoxIcon]::Information)
    })
$panelUser.Controls.Add($btnChangeHost)

$lblHostHint = New-Object System.Windows.Forms.Label
$lblHostHint.Text = "Contoh: AH15X-UNIT-GRED, A151-PC, AH152-NB"
$lblHostHint.Location = New-Object System.Drawing.Point(30, 135)
$lblHostHint.AutoSize = $true
$lblHostHint.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Italic)
$lblHostHint.ForeColor = [System.Drawing.Color]::Gray
$panelUser.Controls.Add($lblHostHint)

function New-UserButton($text, $y) {
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $text
    $btn.Location = New-Object System.Drawing.Point(30, $y)
    $btn.Size = New-Object System.Drawing.Size(600, 45)
    $btn.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $panelUser.Controls.Add($btn)
    return $btn
}

# Helper: Get enabled local users
function Get-EnabledLocalUsers {
    return Get-LocalUser | Where-Object { $_.Enabled -eq $true } | Select-Object -ExpandProperty Name
}

# Helper: Show user picker dialog
function Show-UserPicker($title) {
    $users = Get-EnabledLocalUsers
    if (-not $users -or $users.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Tiada pengguna aktif dijumpai.", "Makluman", 0, 64)
        return $null
    }
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = $title
    $dlg.Size = New-Object System.Drawing.Size(400, 350)
    $dlg.StartPosition = "CenterParent"
    $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "Pilih pengguna:"
    $lbl.Location = New-Object System.Drawing.Point(20, 15)
    $lbl.AutoSize = $true
    $lbl.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $dlg.Controls.Add($lbl)
    
    $lb = New-Object System.Windows.Forms.ListBox
    $lb.Location = New-Object System.Drawing.Point(20, 40)
    $lb.Size = New-Object System.Drawing.Size(340, 200)
    $lb.Font = New-Object System.Drawing.Font("Segoe UI", 11)
    foreach ($u in $users) { $lb.Items.Add($u) | Out-Null }
    $dlg.Controls.Add($lb)
    
    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = "Pilih"
    $btnOk.Location = New-Object System.Drawing.Point(20, 255)
    $btnOk.Size = New-Object System.Drawing.Size(160, 35)
    $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $dlg.Controls.Add($btnOk)
    $dlg.AcceptButton = $btnOk
    
    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Batal"
    $btnCancel.Location = New-Object System.Drawing.Point(200, 255)
    $btnCancel.Size = New-Object System.Drawing.Size(160, 35)
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dlg.Controls.Add($btnCancel)
    $dlg.CancelButton = $btnCancel
    
    $res = $dlg.ShowDialog()
    if ($res -eq [System.Windows.Forms.DialogResult]::OK -and $lb.SelectedItem) {
        return $lb.SelectedItem.ToString()
    }
    return $null
}

# (Microsoft.VisualBasic loaded at init)

$btnAddUser = New-UserButton "1. Tambah Akaun Pengguna Baru" 170
$btnAddUser.Add_Click({
        $typeMsg = "Pilih jenis akaun:`n`n[1] Akaun Administrator`n[2] Akaun Standard`n`nMasukkan pilihan (1/2):"
        $typeChoice = [Microsoft.VisualBasic.Interaction]::InputBox($typeMsg, "Jenis Akaun", "2")
        if (-not $typeChoice -or ($typeChoice -ne "1" -and $typeChoice -ne "2")) { return }
        
        $uname = [Microsoft.VisualBasic.Interaction]::InputBox("Masukkan Login ID pengguna baharu (contoh: pentadbir):", "Tambah Pengguna")
        if ($uname) {
            $netResult = net user $uname /add 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Log "RALAT: Gagal menambah pengguna '$uname'. $netResult"
                [System.Windows.Forms.MessageBox]::Show("Gagal menambah pengguna '$uname'.`n$netResult", "Ralat", 0, [System.Windows.Forms.MessageBoxIcon]::Error)
                return
            }
            if ($typeChoice -eq "1") {
                net localgroup Administrators $uname /add 2>&1 | Out-Null
                $acctType = "Administrator"
            } else {
                # 'net user /add' sudah masukkan ke kumpulan Users secara automatik
                $acctType = "Standard"
            }
            [System.Windows.Forms.MessageBox]::Show("Pengguna '$uname' telah didaftarkan sebagai $acctType tanpa kata laluan.`n(Boleh set di Control Panel)", "Berjaya", 0, [System.Windows.Forms.MessageBoxIcon]::Information)
        }
    })

$btnChangeFullName = New-UserButton "2. Tukar Nama Penuh Pengguna" 225
$btnChangeFullName.Add_Click({
        $uname = Show-UserPicker "Pilih Pengguna - Tukar Nama Penuh"
        if (-not $uname) { return }
        $fullname = [Microsoft.VisualBasic.Interaction]::InputBox("Pengguna: $uname`n`nMasukkan Nama Penuh (Display Name) baharu:", "Tukar Nama Penuh")
        if ($fullname) {
            Set-LocalUser -Name $uname -FullName $fullname -ErrorAction SilentlyContinue
            if ($?) {
                [System.Windows.Forms.MessageBox]::Show("Nama Penuh '$uname' telah dikemaskini kepada '$fullname'.", "Berjaya", 0, [System.Windows.Forms.MessageBoxIcon]::Information)
            } else {
                [System.Windows.Forms.MessageBox]::Show("Gagal menukar Nama Penuh.", "Ralat", 0, [System.Windows.Forms.MessageBoxIcon]::Error)
            }
        }
    })

$btnChangeUserPass = New-UserButton "3. Tukar Kata Laluan Pengguna" 280
$btnChangeUserPass.Add_Click({
        $uname = Show-UserPicker "Pilih Pengguna - Tukar Kata Laluan"
        if (-not $uname) { return }
        $pass = [Microsoft.VisualBasic.Interaction]::InputBox("Pengguna: $uname`n`nMasukkan Kata Laluan baharu:`n(Biarkan kosong untuk buang password)", "Tukar Kata Laluan")
        if ($pass -eq "") {
            net user $uname "" | Out-Null
        } else {
            net user $uname $pass | Out-Null
        }
        if ($?) {
            [System.Windows.Forms.MessageBox]::Show("Kata Laluan untuk '$uname' telah dikemaskini.", "Berjaya", 0, [System.Windows.Forms.MessageBoxIcon]::Information)
        } else {
            [System.Windows.Forms.MessageBox]::Show("Gagal menukar Kata Laluan.", "Ralat", 0, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    })

$btnDeleteUser = New-UserButton "4. Buang Akaun Pengguna" 335
$btnDeleteUser.Add_Click({
        Write-Log "--- Buang Akaun Pengguna ---"
        # Senarai pengguna (kecuali akaun sistem yang dilindungi)
        $protected = @('Administrator', 'DefaultAccount', 'Guest', 'WDAGUtilityAccount', $env:USERNAME)
        $allUsers = Get-LocalUser | Where-Object { $_.Enabled -eq $true -and $_.Name -notin $protected } | Select-Object -ExpandProperty Name
        if (-not $allUsers -or $allUsers.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("Tiada pengguna yang boleh dibuang.`n(Akaun sistem dan akaun semasa dilindungi)", "Makluman", 0, 64)
            return
        }
        # Dialog pilihan pengguna
        $dlg = New-Object System.Windows.Forms.Form
        $dlg.Text = "Buang Akaun Pengguna"
        $dlg.Size = New-Object System.Drawing.Size(420, 400)
        $dlg.StartPosition = "CenterParent"
        $dlg.FormBorderStyle = "FixedDialog"
        $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false
        $lblDel = New-Object System.Windows.Forms.Label
        $lblDel.Text = "Pilih pengguna untuk dibuang:"
        $lblDel.Location = New-Object System.Drawing.Point(20, 15)
        $lblDel.AutoSize = $true
        $lblDel.Font = New-Object System.Drawing.Font("Segoe UI", 10)
        $dlg.Controls.Add($lblDel)
        $lbDel = New-Object System.Windows.Forms.ListBox
        $lbDel.Location = New-Object System.Drawing.Point(20, 40)
        $lbDel.Size = New-Object System.Drawing.Size(360, 200)
        $lbDel.Font = New-Object System.Drawing.Font("Segoe UI", 11)
        foreach ($u in $allUsers) { $lbDel.Items.Add($u) | Out-Null }
        $dlg.Controls.Add($lbDel)
        # Checkbox padam profil sekali
        $chkProfile = New-Object System.Windows.Forms.CheckBox
        $chkProfile.Text = "Padam folder profil pengguna (C:\Users\...)"
        $chkProfile.Location = New-Object System.Drawing.Point(20, 250)
        $chkProfile.AutoSize = $true
        $chkProfile.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $dlg.Controls.Add($chkProfile)
        $btnDelOk = New-Object System.Windows.Forms.Button
        $btnDelOk.Text = "Buang"
        $btnDelOk.Location = New-Object System.Drawing.Point(20, 290)
        $btnDelOk.Size = New-Object System.Drawing.Size(170, 35)
        $btnDelOk.BackColor = [System.Drawing.Color]::FromArgb(192, 57, 43)
        $btnDelOk.ForeColor = [System.Drawing.Color]::White
        $btnDelOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $dlg.Controls.Add($btnDelOk)
        $btnDelCancel = New-Object System.Windows.Forms.Button
        $btnDelCancel.Text = "Batal"
        $btnDelCancel.Location = New-Object System.Drawing.Point(210, 290)
        $btnDelCancel.Size = New-Object System.Drawing.Size(170, 35)
        $btnDelCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $dlg.Controls.Add($btnDelCancel)
        $dlg.AcceptButton = $btnDelOk; $dlg.CancelButton = $btnDelCancel
        $res = $dlg.ShowDialog()
        if ($res -eq [System.Windows.Forms.DialogResult]::OK -and $lbDel.SelectedItem) {
            $target = $lbDel.SelectedItem.ToString()
            $confirmMsg = "AMARAN: Akaun '$target' akan DIBUANG secara kekal."
            if ($chkProfile.Checked) { $confirmMsg += "`n`nFolder profil C:\Users\$target juga akan DIPADAM." }
            $confirmMsg += "`n`nAdakah anda pasti?"
            $confirm = [System.Windows.Forms.MessageBox]::Show($confirmMsg, "Pengesahan Buang Akaun", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
            if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
                $delResult = net user $target /delete 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Log "[OK] Akaun '$target' berjaya dibuang."
                    if ($chkProfile.Checked) {
                        $profilePath = "C:\Users\$target"
                        if (Test-Path $profilePath) {
                            Remove-Item $profilePath -Recurse -Force -ErrorAction SilentlyContinue
                            Write-Log "[OK] Folder profil '$profilePath' dipadam."
                        }
                    }
                    [System.Windows.Forms.MessageBox]::Show("Akaun '$target' berjaya dibuang.", "Berjaya", 0, [System.Windows.Forms.MessageBoxIcon]::Information)
                } else {
                    Write-Log "RALAT: Gagal membuang '$target'. $delResult"
                    [System.Windows.Forms.MessageBox]::Show("Gagal membuang akaun '$target'.`n$delResult", "Ralat", 0, [System.Windows.Forms.MessageBoxIcon]::Error)
                }
            } else { Write-Log "Dibatalkan oleh pengguna." }
        }
    })

$btnToggleUser = New-UserButton "5. Lumpuhkan / Aktifkan Akaun" 390
$btnToggleUser.Add_Click({
        Write-Log "--- Lumpuhkan / Aktifkan Akaun ---"
        $protected = @('Administrator', 'DefaultAccount', 'WDAGUtilityAccount')
        $allAcc = Get-LocalUser | Where-Object { $_.Name -notin $protected } | Select-Object Name, Enabled
        if (-not $allAcc -or $allAcc.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("Tiada akaun dijumpai.", "Makluman", 0, 64); return
        }
        $dlg = New-Object System.Windows.Forms.Form
        $dlg.Text = "Lumpuhkan / Aktifkan Akaun"
        $dlg.Size = New-Object System.Drawing.Size(420, 380)
        $dlg.StartPosition = "CenterParent"
        $dlg.FormBorderStyle = "FixedDialog"
        $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false
        $lblTog = New-Object System.Windows.Forms.Label
        $lblTog.Text = "Pilih akaun (status ditunjukkan):"
        $lblTog.Location = New-Object System.Drawing.Point(20, 15)
        $lblTog.AutoSize = $true
        $lblTog.Font = New-Object System.Drawing.Font("Segoe UI", 10)
        $dlg.Controls.Add($lblTog)
        $lbTog = New-Object System.Windows.Forms.ListBox
        $lbTog.Location = New-Object System.Drawing.Point(20, 40)
        $lbTog.Size = New-Object System.Drawing.Size(360, 210)
        $lbTog.Font = New-Object System.Drawing.Font("Segoe UI", 11)
        foreach ($a in $allAcc) {
            $status = if ($a.Enabled) { "AKTIF" } else { "DILUMPUHKAN" }
            $lbTog.Items.Add("$($a.Name)  [$status]") | Out-Null
        }
        $dlg.Controls.Add($lbTog)
        $btnTogOk = New-Object System.Windows.Forms.Button
        $btnTogOk.Text = "Tukar Status"
        $btnTogOk.Location = New-Object System.Drawing.Point(20, 265)
        $btnTogOk.Size = New-Object System.Drawing.Size(170, 35)
        $btnTogOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $dlg.Controls.Add($btnTogOk)
        $btnTogCancel = New-Object System.Windows.Forms.Button
        $btnTogCancel.Text = "Batal"
        $btnTogCancel.Location = New-Object System.Drawing.Point(210, 265)
        $btnTogCancel.Size = New-Object System.Drawing.Size(170, 35)
        $btnTogCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $dlg.Controls.Add($btnTogCancel)
        $dlg.AcceptButton = $btnTogOk; $dlg.CancelButton = $btnTogCancel
        $res = $dlg.ShowDialog()
        if ($res -eq [System.Windows.Forms.DialogResult]::OK -and $lbTog.SelectedItem) {
            $selText = $lbTog.SelectedItem.ToString()
            $targetName = ($selText -split '\s{2}\[')[0].Trim()
            $acct = Get-LocalUser -Name $targetName -ErrorAction SilentlyContinue
            if ($acct) {
                if ($acct.Enabled) {
                    Disable-LocalUser -Name $targetName -ErrorAction SilentlyContinue
                    Write-Log "[OK] Akaun '$targetName' dilumpuhkan."
                    [System.Windows.Forms.MessageBox]::Show("Akaun '$targetName' telah DILUMPUHKAN.", "Berjaya", 0, 64)
                } else {
                    Enable-LocalUser -Name $targetName -ErrorAction SilentlyContinue
                    Write-Log "[OK] Akaun '$targetName' diaktifkan."
                    [System.Windows.Forms.MessageBox]::Show("Akaun '$targetName' telah DIAKTIFKAN.", "Berjaya", 0, 64)
                }
            }
        }
    })

$btnExportReport = New-UserButton "6. Eksport Laporan Sistem" 445
$btnExportReport.Add_Click({
        Write-Log "--- Eksport Laporan Sistem ---"
        $reportPath = Join-Path $script:LogFolder "SystemReport-$env:COMPUTERNAME-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
        $report = @()
        $report += "=== LAPORAN SISTEM HBUK ==="
        $report += "Tarikh: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        $report += "Hostname: $env:COMPUTERNAME"
        $report += "OS: $((Get-CimInstance Win32_OperatingSystem).Caption)"
        $report += "RAM: $([Math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)) GB"
        $report += ""
        # SPAI
        $svc = Get-Service glpi-agent -ErrorAction SilentlyContinue
        $report += "--- SPAI ---"
        $report += "Status: $(if($svc){$svc.Status}else{'Tidak Dipasang'})"
        $tag = (Get-ItemProperty "HKLM:\SOFTWARE\GLPI-Agent" -Name tag -EA SilentlyContinue).tag
        $report += "Tag: $(if($tag){$tag}else{'N/A'})"
        $report += ""
        # RustDesk
        $rdExeR = if(Test-Path "$env:ProgramFiles\RustDesk\rustdesk.exe"){"$env:ProgramFiles\RustDesk\rustdesk.exe"}elseif(Test-Path "${env:ProgramFiles(x86)}\RustDesk\rustdesk.exe"){"${env:ProgramFiles(x86)}\RustDesk\rustdesk.exe"}else{$null}
        $report += "--- RUSTDESK ---"
        $report += "Status: $(if($rdExeR){'Dipasang'}else{'Tidak Dipasang'})"
        if ($rdExeR) { $report += "Versi: $((Get-Item $rdExeR).VersionInfo.FileVersion -replace '\+.*','')" }
        $report += ""
        # Pengguna
        $report += "--- SENARAI PENGGUNA ---"
        Get-LocalUser | ForEach-Object { $report += "  $($_.Name) | Enabled: $($_.Enabled)" }
        $report | Set-Content -Path $reportPath -Encoding UTF8
        Write-Log "[OK] Laporan disimpan: $reportPath"
        [System.Windows.Forms.MessageBox]::Show("Laporan disimpan ke:`n$reportPath", "Berjaya", 0, 64)
    })

# Combine Panels
$panelContent.Controls.Add($panelMainMenu)
$panelContent.Controls.Add($panelSPAI)
$panelContent.Controls.Add($panelRustDesk)
$panelContent.Controls.Add($panelUser)

# Back buttons for panels
$btnBackSPAI = New-Object System.Windows.Forms.Button
$btnBackSPAI.Text = "< Kembali ke Menu Utama"
$btnBackSPAI.Location = New-Object System.Drawing.Point(450, 20)
$btnBackSPAI.Size = New-Object System.Drawing.Size(230, 35)
$btnBackSPAI.Add_Click({ Show-Panel $panelMainMenu })
$panelSPAI.Controls.Add($btnBackSPAI)
$btnBackSPAI.BringToFront()

$btnBackRD = New-Object System.Windows.Forms.Button
$btnBackRD.Text = "< Kembali ke Menu Utama"
$btnBackRD.Location = New-Object System.Drawing.Point(450, 20)
$btnBackRD.Size = New-Object System.Drawing.Size(230, 35)
$btnBackRD.Add_Click({ Show-Panel $panelMainMenu })
$panelRustDesk.Controls.Add($btnBackRD)
$btnBackRD.BringToFront()

$btnBackUser = New-Object System.Windows.Forms.Button
$btnBackUser.Text = "< Kembali ke Menu Utama"
$btnBackUser.Location = New-Object System.Drawing.Point(450, 20)
$btnBackUser.Size = New-Object System.Drawing.Size(230, 35)
$btnBackUser.Add_Click({ Show-Panel $panelMainMenu })
$panelUser.Controls.Add($btnBackUser)
$btnBackUser.BringToFront()

# Show initial state
Show-Panel $panelMainMenu
Update-SystemInfo
Write-Log "HBUK User Deployment Suite V4.5 dimulakan."
Write-Log "Hostname: $env:COMPUTERNAME | Log: $script:LogFile"

$form.Add_FormClosed({ $script:autoRefreshTimer.Stop(); $script:autoRefreshTimer.Dispose() })
$form.ShowDialog() | Out-Null
