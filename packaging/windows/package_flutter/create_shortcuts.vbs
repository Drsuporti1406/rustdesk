Set ws = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
sm = ws.ExpandEnvironmentStrings("%ProgramData%") & "\Microsoft\Windows\Start Menu\Programs\DrSuporti Remote"
If Not fso.FolderExists(sm) Then fso.CreateFolder(sm)
Set lnk = ws.CreateShortcut(sm & "\DrSuporti Remote.lnk")
lnk.TargetPath = ws.ExpandEnvironmentStrings("%ProgramFiles%") & "\DrSuporti Remote\rustdesk.exe"
lnk.WorkingDirectory = ws.ExpandEnvironmentStrings("%ProgramFiles%") & "\DrSuporti Remote"
lnk.IconLocation = lnk.TargetPath
lnk.Save
desk = ws.ExpandEnvironmentStrings("%Public%") & "\Desktop\DrSuporti Remote.lnk"
Set lnk2 = ws.CreateShortcut(desk)
lnk2.TargetPath = lnk.TargetPath
lnk2.WorkingDirectory = lnk.WorkingDirectory
lnk2.IconLocation = lnk.TargetPath
lnk2.Save
