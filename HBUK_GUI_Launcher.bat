@echo off
:: HBUK USER DEPLOYMENT SUITE — Launcher
:: Fail ini melancarkan skrip utama tanpa tetingkap PowerShell biru.
:: Guna HBUK_GUI_Launcher.vbs untuk lancar tanpa tetingkap CMD sama sekali.
powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0HBUK_USER_DEPLOYMENT_SUITE_V4.3.ps1"
