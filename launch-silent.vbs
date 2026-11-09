Option Explicit

Dim fso, shell, scriptDir, psScript, cmd
Set fso   = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
psScript  = fso.BuildPath(scriptDir, "speedtest-runner.ps1")

cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Sta -File """ & psScript & """"
shell.Run cmd, 0, False
