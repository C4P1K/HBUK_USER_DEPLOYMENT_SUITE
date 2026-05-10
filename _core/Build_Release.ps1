# ============================================================
# Build_Release.ps1 — Jana ZIP bersih untuk pengedaran
# Jalankan skrip ini untuk buat pakej sedia-edar ke rakan sekerja
# ZIP yang dihasilkan TIDAK mengandungi fail pembangunan
# ============================================================

$version = "V4.5"
$rootDir = Split-Path -Parent $PSScriptRoot
if (-not $rootDir) { $rootDir = Split-Path -Parent (Get-Location).Path }

$releaseName = "HBUK_USER_DEPLOYMENT_SUITE_$version"
$outZip = Join-Path $rootDir "$releaseName.zip"

# Senarai fail/folder yang TIDAK perlu dalam ZIP pengedaran
$excludePatterns = @(
    '.git',
    '.gitignore',
    '.gitattributes',
    'README.md',
    'logs',
    '_core\Build_Launcher.ps1',
    '_core\Build_Release.ps1',
    '_core\HBUK_GUI_Launcher.bat'
)

# Buat folder sementara
$tempDir = Join-Path $env:TEMP $releaseName
if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

# Salin semua fail kecuali yang dikecualikan
Write-Host "Menyediakan pakej $releaseName..." -ForegroundColor Cyan

# Salin fail root
$rootFiles = @(
    "HBUK_USER_DEPLOYMENT_SUITE_$version.vbs",
    "HBUK_USER_DEPLOYMENT_SUITE_$version.exe",
    "PANDUAN_PENGGUNA.txt"
)
foreach ($f in $rootFiles) {
    $src = Join-Path $rootDir $f
    if (Test-Path $src) {
        Copy-Item $src -Destination $tempDir
        Write-Host "  [+] $f"
    }
}

# Salin _core (hanya .ps1 utama)
$coreDir = Join-Path $tempDir "_core"
New-Item -ItemType Directory -Path $coreDir -Force | Out-Null
$ps1Src = Join-Path $rootDir "_core\HBUK_USER_DEPLOYMENT_SUITE_$version.ps1"
if (Test-Path $ps1Src) {
    Copy-Item $ps1Src -Destination $coreDir
    Write-Host "  [+] _core\HBUK_USER_DEPLOYMENT_SUITE_$version.ps1"
}

# Salin packages (semua)
$pkgSrc = Join-Path $rootDir "packages"
if (Test-Path $pkgSrc) {
    Copy-Item $pkgSrc -Destination (Join-Path $tempDir "packages") -Recurse
    Write-Host "  [+] packages\ (semua)"
}

# Buat ZIP
if (Test-Path $outZip) { Remove-Item $outZip -Force }
Compress-Archive -Path "$tempDir\*" -DestinationPath $outZip -CompressionLevel Optimal
Remove-Item $tempDir -Recurse -Force

if (Test-Path $outZip) {
    $size = [Math]::Round((Get-Item $outZip).Length / 1MB, 1)
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Green
    Write-Host "[OK] $releaseName.zip berjaya dibina!" -ForegroundColor Green
    Write-Host "Saiz : $size MB" -ForegroundColor Green
    Write-Host "Lokasi: $outZip" -ForegroundColor Green
    Write-Host "============================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Kandungan ZIP:" -ForegroundColor Yellow
    Write-Host "  PANDUAN_PENGGUNA.txt                     <- BACA INI DAHULU"
    Write-Host "  HBUK_USER_DEPLOYMENT_SUITE_$version.vbs  <- Klik ini"
    Write-Host "  HBUK_USER_DEPLOYMENT_SUITE_$version.exe  <- Alternatif"
    Write-Host "  _core\  <- Skrip utama"
    Write-Host "  packages\  <- Installer & config"
} else {
    Write-Host "[!] Gagal membina ZIP." -ForegroundColor Red
}
