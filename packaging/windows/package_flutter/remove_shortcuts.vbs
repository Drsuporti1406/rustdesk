Set fso = CreateObject("Scripting.FileSystemObject")
sm = CreateObject("WScript.Shell").ExpandEnvironmentStrings("%ProgramData%") & "\Microsoft\Windows\Start Menu\Programs\DrSuporti Remote\DrSuporti Remote.lnk"
desk = CreateObject("WScript.Shell").ExpandEnvironmentStrings("%Public%") & "\Desktop\DrSuporti Remote.lnk"
If fso.FileExists(sm) Then fso.DeleteFile(sm)
If fso.FileExists(desk) Then fso.DeleteFile(desk)
