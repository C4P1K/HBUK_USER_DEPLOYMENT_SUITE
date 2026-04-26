@echo off
:: Ini adalah fail 'Launcher' supaya PowerShell tidak disekat (Execution Policy Bypass)
:: -WindowStyle Hidden akan menyorokkan tetingkap biru PowerShell di belakang.

powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0HBUK_Deployment_GUI.ps1"
