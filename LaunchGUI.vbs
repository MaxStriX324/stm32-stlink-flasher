Option Explicit
Dim sh, fs, folder, ps, cmd
Set sh=CreateObject("WScript.Shell")
Set fs=CreateObject("Scripting.FileSystemObject")
folder=fs.GetParentFolderName(WScript.ScriptFullName)
ps=sh.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\WindowsPowerShell\v1.0\powershell.exe"
cmd=Chr(34) & ps & Chr(34) & " -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File " & Chr(34) & folder & "\scripts\gui.ps1" & Chr(34)
sh.CurrentDirectory=folder
sh.Run cmd, 0, False
