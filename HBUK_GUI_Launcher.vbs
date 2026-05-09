' ==============================================================================
' HBUK USER DEPLOYMENT SUITE — Silent Launcher (VBScript)
' Klik dua kali fail ini untuk melancarkan tanpa SEBARANG tetingkap CMD/PowerShell
' AV-selamat: dijalankan oleh wscript.exe (program Windows tulen)
' ==============================================================================
Dim objShell, strDir, strScript
Set objShell = CreateObject("WScript.Shell")

' Dapatkan folder semasa (berfungsi dari mana-mana pemacu USB)
strDir = Left(WScript.ScriptFullName, InStrRev(WScript.ScriptFullName, "\"))
strScript = strDir & "HBUK_USER_DEPLOYMENT_SUITE_V4.3.ps1"

' Semak fail wujud
Dim objFSO
Set objFSO = CreateObject("Scripting.FileSystemObject")
If Not objFSO.FileExists(strScript) Then
    MsgBox "Fail skrip tidak dijumpai:" & vbNewLine & strScript, vbCritical, "HBUK Suite - Ralat"
    WScript.Quit
End If

' Lancar PowerShell tanpa sebarang tetingkap (parameter 0 = tersembunyi)
objShell.Run "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & strScript & """", 0, False

Set objShell = Nothing
Set objFSO = Nothing
