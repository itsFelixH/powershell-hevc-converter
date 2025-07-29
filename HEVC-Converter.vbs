Set objShell = CreateObject("WScript.Shell")
Set objFSO = CreateObject("Scripting.FileSystemObject")

' Get the directory where this VBS file is located
strScriptDir = objFSO.GetParentFolderName(WScript.ScriptFullName)

' Build the PowerShell command
strCommand = "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & strScriptDir & "\HEVC-Converter-GUI.ps1"""

' Run the command without showing any window
objShell.Run strCommand, 0, False