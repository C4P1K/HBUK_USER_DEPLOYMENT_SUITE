# Skrip ini akan mengkompilasi kod C# kecil menjadi fail Executable (.exe)
# yang kalis tetingkap biru.

$sourceCode = @"
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;

namespace HBUKLauncher
{
    class Program
    {
        [STAThread]
        static void Main(string[] args)
        {
            string appDir = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);
            string ps1Path = Path.Combine(appDir, "HBUK_USER_DEPLOYMENT_SUITE_V4.3.ps1");
            
            if (!File.Exists(ps1Path)) {
                System.Windows.Forms.MessageBox.Show("Fail 'HBUK_USER_DEPLOYMENT_SUITE_V4.3.ps1' tidak dijumpai di dalam folder ini.", "Ralat", System.Windows.Forms.MessageBoxButtons.OK, System.Windows.Forms.MessageBoxIcon.Error);
                return;
            }

            ProcessStartInfo startInfo = new ProcessStartInfo();
            startInfo.FileName = "powershell.exe";
            startInfo.Arguments = "-ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + ps1Path + "\"";
            startInfo.CreateNoWindow = true;
            startInfo.UseShellExecute = false;

            try {
                Process.Start(startInfo);
            } catch (Exception ex) {
                System.Windows.Forms.MessageBox.Show(ex.Message);
            }
        }
    }
}
"@

# Cari jalan ke csc.exe (Pengkompil C# sedia ada di dalam PC)
$frameworkPath = [System.Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()
$cscPath = Join-Path $frameworkPath "csc.exe"

$currentDir = $PSScriptRoot
if(-not $currentDir) { $currentDir = (Get-Location).Path }
$outPath = Join-Path $currentDir "HBUK_DEPLOYMENT_SUITE.exe"

$tempFile = Join-Path $env:TEMP "TempLauncher.cs"
Set-Content -Path $tempFile -Value $sourceCode

Write-Host "Sedang membina HBUK_DEPLOYMENT_SUITE.exe..."
& $cscPath /target:winexe /out:"$outPath" /reference:System.Windows.Forms.dll "$tempFile"

if(Test-Path $outPath) {
    Write-Host "[OK] HBUK_DEPLOYMENT_SUITE.exe telah berjaya dibina!" -ForegroundColor Green
} else {
    Write-Host "[!] Gagal membina." -ForegroundColor Red
}

Remove-Item $tempFile -ErrorAction SilentlyContinue
